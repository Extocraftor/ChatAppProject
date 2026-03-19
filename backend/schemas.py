from pydantic import BaseModel
from datetime import datetime
from typing import List, Literal, Optional

class MessageBase(BaseModel):
    content: str

class MessageCreate(MessageBase):
    user_id: int
    channel_id: int
    parent_id: Optional[int] = None

class MessageSchema(MessageBase):
    id: int
    timestamp: datetime
    user_id: int
    username: str
    channel_id: int
    parent_id: Optional[int] = None
    parent_username: Optional[str] = None
    parent_content: Optional[str] = None

    class Config:
        from_attributes = True

class ChannelBase(BaseModel):
    name: str
    description: Optional[str] = None

class ChannelCreate(ChannelBase):
    pass

class ChannelSchema(ChannelBase):
    id: int
    creator_user_id: Optional[int] = None
    messages: List[MessageSchema] = []

    class Config:
        from_attributes = True


class VoiceChannelBase(BaseModel):
    name: str
    description: Optional[str] = None


class VoiceChannelCreate(VoiceChannelBase):
    pass


class VoiceChannelSchema(VoiceChannelBase):
    id: int
    creator_user_id: Optional[int] = None

    class Config:
        from_attributes = True


class VoiceParticipantSchema(BaseModel):
    user_id: int
    username: str
    is_muted: bool = False


class UserBase(BaseModel):
    username: str

class UserCreate(UserBase):
    password: str

class UserSchema(UserBase):
    id: int
    role: str

    class Config:
        from_attributes = True


class UserRoleUpdate(BaseModel):
    role: Literal["member", "moderator", "admin"]
