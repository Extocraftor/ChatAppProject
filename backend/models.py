from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import relationship
from datetime import datetime
from database import Base


class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    username = Column(String, unique=True, index=True)
    hashed_password = Column(String)
    role = Column(String, default="member", nullable=False)
    messages = relationship("Message", back_populates="user")
    created_channels = relationship(
        "Channel",
        back_populates="creator",
        foreign_keys="Channel.creator_user_id",
    )
    created_voice_channels = relationship(
        "VoiceChannel",
        back_populates="creator",
        foreign_keys="VoiceChannel.creator_user_id",
    )
    text_channel_permissions = relationship(
        "TextChannelPermission",
        back_populates="user",
        cascade="all, delete-orphan",
    )
    voice_channel_permissions = relationship(
        "VoiceChannelPermission",
        back_populates="user",
        cascade="all, delete-orphan",
    )


class Channel(Base):
    __tablename__ = "channels"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, index=True)
    description = Column(String)
    creator_user_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    messages = relationship("Message", back_populates="channel")
    creator = relationship(
        "User",
        back_populates="created_channels",
        foreign_keys=[creator_user_id],
    )
    permissions = relationship(
        "TextChannelPermission",
        back_populates="channel",
        cascade="all, delete-orphan",
    )


class VoiceChannel(Base):
    __tablename__ = "voice_channels"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, index=True)
    description = Column(String)
    creator_user_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    creator = relationship(
        "User",
        back_populates="created_voice_channels",
        foreign_keys=[creator_user_id],
    )
    permissions = relationship(
        "VoiceChannelPermission",
        back_populates="channel",
        cascade="all, delete-orphan",
    )


class TextChannelPermission(Base):
    __tablename__ = "text_channel_permissions"
    __table_args__ = (
        UniqueConstraint("user_id", "channel_id", name="uq_text_channel_permissions_user_channel"),
    )

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    channel_id = Column(Integer, ForeignKey("channels.id"), nullable=False, index=True)
    can_view = Column(Boolean, nullable=False, default=True)

    user = relationship("User", back_populates="text_channel_permissions")
    channel = relationship("Channel", back_populates="permissions")


class VoiceChannelPermission(Base):
    __tablename__ = "voice_channel_permissions"
    __table_args__ = (
        UniqueConstraint("user_id", "channel_id", name="uq_voice_channel_permissions_user_channel"),
    )

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    channel_id = Column(Integer, ForeignKey("voice_channels.id"), nullable=False, index=True)
    can_view = Column(Boolean, nullable=False, default=True)

    user = relationship("User", back_populates="voice_channel_permissions")
    channel = relationship("VoiceChannel", back_populates="permissions")


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
