from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import inspect, text
from sqlalchemy.orm import Session, joinedload
from typing import Any, Dict, List
import json
import os
import logging

from database import SessionLocal, engine, get_db
import models, schemas
from passlib.context import CryptContext

# Password hashing configuration
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def get_password_hash(password: str) -> str:
    # Bcrypt has a 72-byte limit. We truncate to 64 for extra safety.
    return pwd_context.hash(password[:64])


def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password[:64], hashed_password)


ROLE_MEMBER = "member"
ROLE_MODERATOR = "moderator"
ROLE_ADMIN = "admin"


def _parse_username_set(env_name: str) -> set[str]:
    raw = os.getenv(env_name, "")
    return {item.strip().lower() for item in raw.split(",") if item.strip()}


ADMIN_USERNAMES = _parse_username_set("ADMIN_USERNAMES")
MODERATOR_USERNAMES = _parse_username_set("MODERATOR_USERNAMES")


def _ensure_schema_columns() -> None:
    inspector = inspect(engine)

    with engine.begin() as conn:
        user_columns = {column["name"] for column in inspector.get_columns("users")}
        if "role" not in user_columns:
            conn.execute(
                text("ALTER TABLE users ADD COLUMN role VARCHAR NOT NULL DEFAULT 'member'")
            )

        channel_columns = {
            column["name"] for column in inspector.get_columns("channels")
        }
        if "creator_user_id" not in channel_columns:
            conn.execute(
                text("ALTER TABLE channels ADD COLUMN creator_user_id INTEGER")
            )

        voice_channel_columns = {
            column["name"] for column in inspector.get_columns("voice_channels")
        }
        if "creator_user_id" not in voice_channel_columns:
            conn.execute(
                text("ALTER TABLE voice_channels ADD COLUMN creator_user_id INTEGER")
            )


def _seed_existing_user_roles() -> None:
    db = SessionLocal()
    try:
        users = db.query(models.User).all()
        if not users:
            return

        changed = False
        for user in users:
            normalized_username = user.username.strip().lower()
            desired_role = None
            if normalized_username in ADMIN_USERNAMES:
                desired_role = ROLE_ADMIN
            elif (
                normalized_username in MODERATOR_USERNAMES
                and user.role != ROLE_ADMIN
            ):
                desired_role = ROLE_MODERATOR

            if desired_role and user.role != desired_role:
                user.role = desired_role
                changed = True

        has_admin = any(user.role == ROLE_ADMIN for user in users)
        if not has_admin:
            first_user = min(users, key=lambda user: user.id)
            first_user.role = ROLE_ADMIN
            changed = True

        if changed:
            db.commit()
    finally:
        db.close()


# Create all tables on startup
models.Base.metadata.create_all(bind=engine)
_ensure_schema_columns()
_seed_existing_user_roles()

app = FastAPI()
logger = logging.getLogger("uvicorn.error")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Connection Manager for text channels
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
        connections = self.active_connections.get(channel_id)
        if not connections:
            return
        if websocket in connections:
            connections.remove(websocket)
        if not connections:
            self.active_connections.pop(channel_id, None)

    async def broadcast(self, message: str, channel_id: int):
        connections = self.active_connections.get(channel_id, [])
        for connection in list(connections):
            try:
                await connection.send_text(message)
            except Exception:
                self.disconnect(connection, channel_id)

    async def close_channel(self, channel_id: int):
        connections = self.active_connections.pop(channel_id, [])
        for connection in list(connections):
            try:
                await connection.close(code=1008)
            except Exception:
                pass


# Connection manager for voice channels/WebRTC signaling
class VoiceConnectionManager:
    def __init__(self):
        # channel_id -> user_id -> websocket
        self.active_connections: Dict[int, Dict[int, WebSocket]] = {}
        # channel_id -> user_id -> username
        self.usernames: Dict[int, Dict[int, str]] = {}
        # channel_id -> user_id -> muted state
        self.mute_states: Dict[int, Dict[int, bool]] = {}

    async def connect(self, websocket: WebSocket, channel_id: int, user_id: int, username: str):
        await websocket.accept()
        if channel_id not in self.active_connections:
            self.active_connections[channel_id] = {}
        if channel_id not in self.usernames:
            self.usernames[channel_id] = {}
        if channel_id not in self.mute_states:
            self.mute_states[channel_id] = {}

        # If the same user reconnects quickly, close the stale socket first.
        existing_socket = self.active_connections[channel_id].get(user_id)
        if existing_socket is not None and existing_socket is not websocket:
            try:
                await existing_socket.close(code=1000)
            except Exception:
                pass

        self.active_connections[channel_id][user_id] = websocket
        self.usernames[channel_id][user_id] = username
        self.mute_states[channel_id].setdefault(user_id, False)

    def disconnect(self, channel_id: int, user_id: int, websocket: WebSocket | None = None) -> bool:
        removed = False
        if channel_id in self.active_connections:
            channel_connections = self.active_connections[channel_id]
            current_socket = channel_connections.get(user_id)
            # Ignore stale-disconnect callbacks from sockets that were replaced.
            if websocket is not None and current_socket is not websocket:
                return False

            if user_id in channel_connections:
                channel_connections.pop(user_id, None)
                removed = True
            if not channel_connections:
                self.active_connections.pop(channel_id, None)

        if channel_id in self.usernames:
            self.usernames[channel_id].pop(user_id, None)
            if not self.usernames[channel_id]:
                self.usernames.pop(channel_id, None)

        if channel_id in self.mute_states:
            self.mute_states[channel_id].pop(user_id, None)
            if not self.mute_states[channel_id]:
                self.mute_states.pop(channel_id, None)
        return removed

    def participants(self, channel_id: int) -> List[Dict[str, Any]]:
        usernames = self.usernames.get(channel_id, {})
        mute_states = self.mute_states.get(channel_id, {})
        return [
            {
                "user_id": user_id,
                "username": usernames.get(user_id, f"User #{user_id}"),
                "is_muted": mute_states.get(user_id, False),
            }
            for user_id in usernames.keys()
        ]

    def update_mute_state(self, channel_id: int, user_id: int, is_muted: bool):
        if channel_id not in self.mute_states:
            self.mute_states[channel_id] = {}
        self.mute_states[channel_id][user_id] = is_muted

    async def send_to_user(self, channel_id: int, user_id: int, payload: Dict[str, Any]):
        channel_connections = self.active_connections.get(channel_id, {})
        websocket = channel_connections.get(user_id)
        if websocket is None:
            return

        try:
            await websocket.send_text(json.dumps(payload))
        except Exception:
            self.disconnect(channel_id, user_id, websocket=websocket)

    async def broadcast(self, channel_id: int, payload: Dict[str, Any], exclude_user_id: int | None = None):
        channel_connections = self.active_connections.get(channel_id, {})
        for user_id in list(channel_connections.keys()):
            if exclude_user_id is not None and user_id == exclude_user_id:
                continue
            await self.send_to_user(channel_id, user_id, payload)

    async def close_channel(self, channel_id: int):
        channel_connections = self.active_connections.pop(channel_id, {})
        self.usernames.pop(channel_id, None)
        self.mute_states.pop(channel_id, None)
        for websocket in list(channel_connections.values()):
            try:
                await websocket.close(code=1008)
            except Exception:
                pass


manager = ConnectionManager()
voice_manager = VoiceConnectionManager()


def _resolve_user_role(username: str, db: Session) -> str:
    normalized_username = username.strip().lower()
    if normalized_username in ADMIN_USERNAMES:
        return ROLE_ADMIN
    if normalized_username in MODERATOR_USERNAMES:
        return ROLE_MODERATOR

    user_count = db.query(models.User.id).count()
    if user_count == 0:
        return ROLE_ADMIN

    return ROLE_MEMBER


def _is_staff(user: models.User) -> bool:
    return user.role in {ROLE_ADMIN, ROLE_MODERATOR}


def _ensure_actor_user(db: Session, actor_user_id: int) -> models.User:
    actor_user = db.query(models.User).filter(models.User.id == actor_user_id).first()
    if not actor_user:
        raise HTTPException(status_code=404, detail="Actor user not found")
    return actor_user


# --- REST ENDPOINTS ---


@app.post("/users/", response_model=schemas.UserSchema)
def create_user(user: schemas.UserCreate, db: Session = Depends(get_db)):
    existing_user = db.query(models.User).filter(models.User.username == user.username).first()
    if existing_user:
        raise HTTPException(status_code=400, detail="Username already registered")

    hashed_pwd = get_password_hash(user.password)
    role = _resolve_user_role(user.username, db)
    db_user = models.User(
        username=user.username,
        hashed_password=hashed_pwd,
        role=role,
    )
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


@app.patch("/users/{target_user_id}/role", response_model=schemas.UserSchema)
def update_user_role(
    target_user_id: int,
    role_update: schemas.UserRoleUpdate,
    actor_user_id: int,
    db: Session = Depends(get_db),
):
    actor_user = _ensure_actor_user(db, actor_user_id)
    if actor_user.role != ROLE_ADMIN:
        raise HTTPException(status_code=403, detail="Only admins can update roles")

    target_user = db.query(models.User).filter(models.User.id == target_user_id).first()
    if not target_user:
        raise HTTPException(status_code=404, detail="Target user not found")

    target_user.role = role_update.role
    db.commit()
    db.refresh(target_user)
    return target_user


@app.post("/login/", response_model=schemas.UserSchema)
def login(user: schemas.UserCreate, db: Session = Depends(get_db)):
    db_user = db.query(models.User).filter(models.User.username == user.username).first()
    if not db_user or not verify_password(user.password, db_user.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid username or password")
    return db_user


@app.post("/channels/", response_model=schemas.ChannelSchema)
def create_channel(
    channel: schemas.ChannelCreate,
    actor_user_id: int | None = None,
    db: Session = Depends(get_db),
):
    creator_user_id = None
    if actor_user_id is not None:
        actor_user = _ensure_actor_user(db, actor_user_id)
        creator_user_id = actor_user.id

    db_channel = models.Channel(
        name=channel.name,
        description=channel.description,
        creator_user_id=creator_user_id,
    )
    db.add(db_channel)
    db.commit()
    db.refresh(db_channel)
    return db_channel


@app.get("/channels/", response_model=List[schemas.ChannelSchema])
def list_channels(db: Session = Depends(get_db)):
    return db.query(models.Channel).all()


@app.delete("/channels/{channel_id}")
async def delete_channel(channel_id: int, actor_user_id: int, db: Session = Depends(get_db)):
    actor_user = _ensure_actor_user(db, actor_user_id)

    db_channel = db.query(models.Channel).filter(models.Channel.id == channel_id).first()
    if not db_channel:
        raise HTTPException(status_code=404, detail="Channel not found")

    can_delete = _is_staff(actor_user) or (
        db_channel.creator_user_id is not None and db_channel.creator_user_id == actor_user.id
    )
    if not can_delete:
        raise HTTPException(
            status_code=403,
            detail="Only moderators/admins or the channel creator can delete this channel",
        )

    await manager.close_channel(channel_id)
    db.query(models.Message).filter(models.Message.channel_id == channel_id).delete(
        synchronize_session=False
    )
    db.delete(db_channel)
    db.commit()
    return {"detail": "Channel deleted"}


@app.get("/channels/{channel_id}/messages/", response_model=List[schemas.MessageSchema])
def get_messages(channel_id: int, db: Session = Depends(get_db)):
    return (
        db.query(models.Message)
        .options(joinedload(models.Message.user))
        .filter(models.Message.channel_id == channel_id)
        .order_by(models.Message.timestamp.asc())
        .all()
    )


@app.post("/voice-channels/", response_model=schemas.VoiceChannelSchema)
def create_voice_channel(
    channel: schemas.VoiceChannelCreate,
    actor_user_id: int | None = None,
    db: Session = Depends(get_db),
):
    creator_user_id = None
    if actor_user_id is not None:
        actor_user = _ensure_actor_user(db, actor_user_id)
        creator_user_id = actor_user.id

    existing_channel = (
        db.query(models.VoiceChannel)
        .filter(models.VoiceChannel.name == channel.name)
        .first()
    )
    if existing_channel:
        raise HTTPException(status_code=400, detail="Voice channel already exists")

    db_channel = models.VoiceChannel(
        name=channel.name,
        description=channel.description,
        creator_user_id=creator_user_id,
    )
    db.add(db_channel)
    try:
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="Error creating voice channel")

    db.refresh(db_channel)
    return db_channel


@app.get("/voice-channels/", response_model=List[schemas.VoiceChannelSchema])
def list_voice_channels(db: Session = Depends(get_db)):
    return db.query(models.VoiceChannel).order_by(models.VoiceChannel.name.asc()).all()


@app.delete("/voice-channels/{voice_channel_id}")
async def delete_voice_channel(
    voice_channel_id: int,
    actor_user_id: int,
    db: Session = Depends(get_db),
):
    actor_user = _ensure_actor_user(db, actor_user_id)
    db_voice_channel = (
        db.query(models.VoiceChannel)
        .filter(models.VoiceChannel.id == voice_channel_id)
        .first()
    )
    if not db_voice_channel:
        raise HTTPException(status_code=404, detail="Voice channel not found")

    can_delete = _is_staff(actor_user) or (
        db_voice_channel.creator_user_id is not None
        and db_voice_channel.creator_user_id == actor_user.id
    )
    if not can_delete:
        raise HTTPException(
            status_code=403,
            detail=(
                "Only moderators/admins or the channel creator can delete this voice channel"
            ),
        )

    await voice_manager.close_channel(voice_channel_id)
    db.delete(db_voice_channel)
    db.commit()
    return {"detail": "Voice channel deleted"}


@app.get(
    "/voice-channels/{voice_channel_id}/participants/",
    response_model=List[schemas.VoiceParticipantSchema],
)
def list_voice_channel_participants(voice_channel_id: int):
    return voice_manager.participants(voice_channel_id)


# --- WEBSOCKET ENDPOINTS ---


@app.websocket("/ws/{channel_id}/{user_id}")
async def websocket_endpoint(
    websocket: WebSocket,
    channel_id: int,
    user_id: int,
    db: Session = Depends(get_db),
):
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
                    db_message = models.Message(
                        content=content,
                        user_id=user_id,
                        channel_id=channel_id,
                        parent_id=parent_id,
                    )
                    db.add(db_message)
                    db.commit()
                    db.refresh(db_message)

                    broadcast_msg = json.dumps(
                        {
                            "type": "new_message",
                            "id": db_message.id,
                            "user_id": user_id,
                            "username": username,
                            "content": content,
                            "timestamp": str(db_message.timestamp),
                            "parent_id": db_message.parent_id,
                            "parent_username": db_message.parent_username,
                            "parent_content": db_message.parent_content,
                        }
                    )

                elif msg_type == "edit_message":
                    msg_id = data_json.get("id")
                    db_message = (
                        db.query(models.Message)
                        .filter(models.Message.id == msg_id, models.Message.user_id == user_id)
                        .first()
                    )
                    if not db_message:
                        continue

                    db_message.content = content
                    db.commit()
                    db.refresh(db_message)

                    broadcast_msg = json.dumps(
                        {
                            "type": "edit_message",
                            "id": db_message.id,
                            "content": content,
                        }
                    )

                elif msg_type == "delete_message":
                    msg_id = data_json.get("id")
                    db_message = (
                        db.query(models.Message)
                        .filter(models.Message.id == msg_id, models.Message.user_id == user_id)
                        .first()
                    )
                    if not db_message:
                        continue

                    db.delete(db_message)
                    db.commit()

                    broadcast_msg = json.dumps(
                        {
                            "type": "delete_message",
                            "id": msg_id,
                        }
                    )
                else:
                    continue

                await manager.broadcast(broadcast_msg, channel_id)

            except json.JSONDecodeError:
                db_message = models.Message(content=data_str, user_id=user_id, channel_id=channel_id)
                db.add(db_message)
                db.commit()
                db.refresh(db_message)
                broadcast_msg = json.dumps(
                    {
                        "type": "new_message",
                        "id": db_message.id,
                        "user_id": user_id,
                        "username": username,
                        "content": data_str,
                        "timestamp": str(db_message.timestamp),
                    }
                )
                await manager.broadcast(broadcast_msg, channel_id)

    except WebSocketDisconnect:
        manager.disconnect(websocket, channel_id)


@app.websocket("/ws/voice/{voice_channel_id}/{user_id}")
async def voice_websocket_endpoint(
    websocket: WebSocket,
    voice_channel_id: int,
    user_id: int,
    db: Session = Depends(get_db),
):
    db_user = db.query(models.User).filter(models.User.id == user_id).first()
    if not db_user:
        await websocket.close(code=1008)
        return

    db_voice_channel = (
        db.query(models.VoiceChannel)
        .filter(models.VoiceChannel.id == voice_channel_id)
        .first()
    )
    if not db_voice_channel:
        await websocket.close(code=1008)
        return

    username = db_user.username
    await voice_manager.connect(websocket, voice_channel_id, user_id, username)
    logger.info("voice connect channel=%s user=%s", voice_channel_id, user_id)

    await voice_manager.send_to_user(
        voice_channel_id,
        user_id,
        {
            "type": "voice_state",
            "participants": voice_manager.participants(voice_channel_id),
        },
    )

    await voice_manager.broadcast(
        voice_channel_id,
        {
            "type": "participant_joined",
            "user_id": user_id,
            "username": username,
            "is_muted": voice_manager.mute_states.get(voice_channel_id, {}).get(user_id, False),
        },
        exclude_user_id=user_id,
    )

    try:
        while True:
            data_str = await websocket.receive_text()
            try:
                data_json = json.loads(data_str)
            except json.JSONDecodeError:
                continue

            msg_type = data_json.get("type")

            if msg_type in {"offer", "answer", "ice_candidate"}:
                target_user_id = data_json.get("target_user_id")
                if target_user_id is None:
                    continue

                try:
                    target_user_id = int(target_user_id)
                except (TypeError, ValueError):
                    continue

                relay_payload: Dict[str, Any] = {
                    "type": msg_type,
                    "from_user_id": user_id,
                    "username": username,
                }

                if msg_type in {"offer", "answer"}:
                    relay_payload["sdp"] = data_json.get("sdp")
                else:
                    relay_payload["candidate"] = data_json.get("candidate")

                await voice_manager.send_to_user(voice_channel_id, target_user_id, relay_payload)

            elif msg_type == "mute_state":
                is_muted = bool(data_json.get("is_muted", False))
                voice_manager.update_mute_state(voice_channel_id, user_id, is_muted)
                await voice_manager.broadcast(
                    voice_channel_id,
                    {
                        "type": "mute_state",
                        "user_id": user_id,
                        "is_muted": is_muted,
                    },
                )

            elif msg_type == "ping":
                pong_payload: Dict[str, Any] = {"type": "pong"}
                ping_id = data_json.get("ping_id")
                if ping_id is not None:
                    try:
                        pong_payload["ping_id"] = int(ping_id)
                    except (TypeError, ValueError):
                        pass
                await voice_manager.send_to_user(voice_channel_id, user_id, pong_payload)

    except WebSocketDisconnect as disconnect_event:
        logger.info(
            "voice disconnect channel=%s user=%s code=%s",
            voice_channel_id,
            user_id,
            disconnect_event.code,
        )
    except Exception:
        logger.exception("voice socket error channel=%s user=%s", voice_channel_id, user_id)
    finally:
        removed = voice_manager.disconnect(
            voice_channel_id,
            user_id,
            websocket=websocket,
        )
        if removed:
            await voice_manager.broadcast(
                voice_channel_id,
                {
                    "type": "participant_left",
                    "user_id": user_id,
                },
            )


if __name__ == "__main__":
    import uvicorn

    ws_ping_interval = float(os.getenv("WS_PING_INTERVAL", "30"))
    ws_ping_timeout = float(os.getenv("WS_PING_TIMEOUT", "120"))

    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8000,
        ws_ping_interval=ws_ping_interval,
        ws_ping_timeout=ws_ping_timeout,
    )
