import os
from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

load_dotenv()

SQLALCHEMY_DATABASE_URL = os.getenv("DATABASE_URL")

if not SQLALCHEMY_DATABASE_URL:
    SQLALCHEMY_DATABASE_URL = "postgresql://postgres:formula1@localhost/chatapp"

if SQLALCHEMY_DATABASE_URL.startswith("postgres://"):
    SQLALCHEMY_DATABASE_URL = SQLALCHEMY_DATABASE_URL.replace("postgres://", "postgresql://", 1)

# Add SSL requirement for cloud databases (Render/Railway/etc)
connect_args = {}
if "localhost" not in SQLALCHEMY_DATABASE_URL and "127.0.0.1" not in SQLALCHEMY_DATABASE_URL:
    connect_args["sslmode"] = "require"

try:
    engine = create_engine(
        SQLALCHEMY_DATABASE_URL, 
        connect_args=connect_args,
        pool_pre_ping=True # Helps with connection stability
    )
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    print("Database engine initialized successfully.")
except Exception as e:
    print(f"Error initializing database engine: {e}")

Base = declarative_base()

# Dependency to get a database session in FastAPI routes
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
