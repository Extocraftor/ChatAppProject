from pydantic import BaseModel, Field
from datetime import datetime
from typing import Dict, List, Literal, Optional

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
    is_pinned: bool = False
    pinned_at: Optional[datetime] = None
    pinned_by_user_id: Optional[int] = None
    pinned_by_username: Optional[str] = None
    attachment_url: Optional[str] = None
    attachment_name: Optional[str] = None
    attachment_content_type: Optional[str] = None
    attachment_size: Optional[int] = None
    mentioned_user_ids: List[int] = Field(default_factory=list)
    mentioned_usernames: List[str] = Field(default_factory=list)

    class Config:
        from_attributes = True

class ChannelBase(BaseModel):
    name: str
    description: Optional[str] = None

class ChannelCreate(ChannelBase):
    admin_only: bool = False

class ChannelSchema(ChannelBase):
    id: int
    admin_only: bool = False
    creator_user_id: Optional[int] = None
    messages: List[MessageSchema] = []

    class Config:
        from_attributes = True


class VoiceChannelBase(BaseModel):
    name: str
    description: Optional[str] = None


class VoiceChannelCreate(VoiceChannelBase):
    admin_only: bool = False


class VoiceChannelSchema(VoiceChannelBase):
    id: int
    admin_only: bool = False
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


class ChannelVisibilityPermissionSchema(BaseModel):
    channel_id: int
    channel_name: str
    can_view: bool


class UserChannelPermissionsSchema(BaseModel):
    user_id: int
    username: str
    role: str
    text_channel_permissions: List[ChannelVisibilityPermissionSchema]
    voice_channel_permissions: List[ChannelVisibilityPermissionSchema]


class UserChannelPermissionsUpdate(BaseModel):
    text_channel_permissions: Dict[int, bool] = {}
    voice_channel_permissions: Dict[int, bool] = {}


class ChannelUserVisibilitySchema(BaseModel):
    user_id: int
    username: str
    role: str
    can_view: bool


class ChannelPermissionsSchema(BaseModel):
    channel_id: int
    channel_name: str
    channel_type: Literal["text", "voice"]
    users: List[ChannelUserVisibilitySchema]


class ChannelPermissionsUpdate(BaseModel):
    user_permissions: Dict[int, bool] = {}
