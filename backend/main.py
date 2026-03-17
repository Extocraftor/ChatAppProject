from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session, joinedload
from typing import List, Dict
import json

from database import engine, Base, get_db
import models, schemas
from passlib.context import CryptContext

# Password hashing configuration
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def get_password_hash(password):
    # Bcrypt has a 72-byte limit. We truncate to prevent ValueErrors.
    return pwd_context.hash(password[:72])

def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password[:72], hashed_password)

# Create all tables on startup
models.Base.metadata.create_all(bind=engine)

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Connection Manager for Rooms/Channels
class ConnectionManager:
    def __init__(self):
        # Maps channel_id to a list of active WebSockets
        self.active_connections: Dict[int, List[WebSocket]] = {}

    async def connect(self, websocket: WebSocket, channel_id: int):
        await websocket.accept()
        if channel_id not in self.active_connections:
            self.active_connections[channel_id] = []
        self.active_connections[channel_id].append(websocket)

    def disconnect(self, websocket: WebSocket, channel_id: int):
        if channel_id in self.active_connections:
            self.active_connections[channel_id].remove(websocket)

    async def broadcast(self, message: str, channel_id: int):
        if channel_id in self.active_connections:
            for connection in self.active_connections[channel_id]:
                await connection.send_text(message)

manager = ConnectionManager()

# --- REST ENDPOINTS ---

@app.post("/users/", response_model=schemas.UserSchema)
def create_user(user: schemas.UserCreate, db: Session = Depends(get_db)):
    # Check if username exists
    existing_user = db.query(models.User).filter(models.User.username == user.username).first()
    if existing_user:
        raise HTTPException(status_code=400, detail="Username already registered")
    
    hashed_pwd = get_password_hash(user.password)
    db_user = models.User(username=user.username, hashed_password=hashed_pwd)
    db.add(db_user)
    try:
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="Error creating user")
    db.refresh(db_user)
    return db_user

@app.get("/users/", response_model=List[schemas.UserSchema])
def list_users(db: Session = Depends(get_db)):
    return db.query(models.User).all()

@app.post("/login/", response_model=schemas.UserSchema)
def login(user: schemas.UserCreate, db: Session = Depends(get_db)):
    db_user = db.query(models.User).filter(models.User.username == user.username).first()
    if not db_user or not verify_password(user.password, db_user.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid username or password")
    return db_user

@app.post("/channels/", response_model=schemas.ChannelSchema)
def create_channel(channel: schemas.ChannelCreate, db: Session = Depends(get_db)):
    db_channel = models.Channel(name=channel.name, description=channel.description)
    db.add(db_channel)
    db.commit()
    db.refresh(db_channel)
    return db_channel

@app.get("/channels/", response_model=List[schemas.ChannelSchema])
def list_channels(db: Session = Depends(get_db)):
    return db.query(models.Channel).all()

@app.get("/channels/{channel_id}/messages/", response_model=List[schemas.MessageSchema])
def get_messages(channel_id: int, db: Session = Depends(get_db)):
    return db.query(models.Message).options(joinedload(models.Message.user)).filter(models.Message.channel_id == channel_id).order_by(models.Message.timestamp.asc()).all()

# --- WEBSOCKET ENDPOINT ---

@app.websocket("/ws/{channel_id}/{user_id}")
async def websocket_endpoint(websocket: WebSocket, channel_id: int, user_id: int, db: Session = Depends(get_db)):
    await manager.connect(websocket, channel_id)
    db_user = db.query(models.User).filter(models.User.id == user_id).first()
    username = db_user.username if db_user else "Unknown"

    try:
        while True:
            data_str = await websocket.receive_text()
            try:
                data_json = json.loads(data_str)
                msg_type = data_json.get("type", "new_message")
                content = data_json.get("content")
                
                if msg_type == "new_message":
                    parent_id = data_json.get("parent_id")
                    db_message = models.Message(content=content, user_id=user_id, channel_id=channel_id, parent_id=parent_id)
                    db.add(db_message)
                    db.commit()
                    db.refresh(db_message)
                    
                    broadcast_msg = json.dumps({
                        "type": "new_message",
                        "id": db_message.id,
                        "user_id": user_id,
                        "username": username,
                        "content": content,
                        "timestamp": str(db_message.timestamp),
                        "parent_id": db_message.parent_id,
                        "parent_username": db_message.parent_username,
                        "parent_content": db_message.parent_content
                    })
                
                elif msg_type == "edit_message":
                    msg_id = data_json.get("id")
                    db_message = db.query(models.Message).filter(models.Message.id == msg_id, models.Message.user_id == user_id).first()
                    if db_message:
                        db_message.content = content
                        db.commit()
                        db.refresh(db_message)
                        
                        broadcast_msg = json.dumps({
                            "type": "edit_message",
                            "id": db_message.id,
                            "content": content
                        })
                    else:
                        continue
                
                elif msg_type == "delete_message":
                    msg_id = data_json.get("id")
                    db_message = db.query(models.Message).filter(models.Message.id == msg_id, models.Message.user_id == user_id).first()
                    if db_message:
                        # Before deleting, null out parent_id of any replies to prevent FK errors or delete them too
                        # For simplicity, we'll just delete the message. 
                        # SQLAlchemy handles FKs based on how you set up the model.
                        db.delete(db_message)
                        db.commit()
                        
                        broadcast_msg = json.dumps({
                            "type": "delete_message",
                            "id": msg_id
                        })
                    else:
                        continue
                
                await manager.broadcast(broadcast_msg, channel_id)
                
            except json.JSONDecodeError:
                # Fallback for simple text (legacy/simple clients)
                db_message = models.Message(content=data_str, user_id=user_id, channel_id=channel_id)
                db.add(db_message)
                db.commit()
                db.refresh(db_message)
                broadcast_msg = json.dumps({
                    "type": "new_message",
                    "id": db_message.id,
                    "user_id": user_id,
                    "username": username,
                    "content": data_str,
                    "timestamp": str(db_message.timestamp)
                })
                await manager.broadcast(broadcast_msg, channel_id)
            
    except WebSocketDisconnect:
        manager.disconnect(websocket, channel_id)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
