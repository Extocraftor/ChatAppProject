from sqlalchemy import Column, Integer, String, ForeignKey, DateTime
from sqlalchemy.orm import relationship
from datetime import datetime
from database import Base

class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    username = Column(String, unique=True, index=True)
    hashed_password = Column(String)
    messages = relationship("Message", back_populates="user")

class Channel(Base):
    __tablename__ = "channels"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, index=True)
    description = Column(String)
    messages = relationship("Message", back_populates="channel")


class VoiceChannel(Base):
    __tablename__ = "voice_channels"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, index=True)
    description = Column(String)


class Message(Base):
    __tablename__ = "messages"
    id = Column(Integer, primary_key=True, index=True)
    content = Column(String)
    timestamp = Column(DateTime, default=datetime.utcnow)
    user_id = Column(Integer, ForeignKey("users.id"))
    channel_id = Column(Integer, ForeignKey("channels.id"))
    parent_id = Column(Integer, ForeignKey("messages.id"), nullable=True)
    
    user = relationship("User", back_populates="messages")
    channel = relationship("Channel", back_populates="messages")
    parent = relationship("Message", remote_side=[id], backref="replies")

    @property
    def username(self):
        return self.user.username if self.user else "Unknown"

    @property
    def parent_username(self):
        return self.parent.user.username if self.parent and self.parent.user else None

    @property
    def parent_content(self):
        return self.parent.content if self.parent else None
