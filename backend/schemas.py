import re
from pydantic import BaseModel, Field, field_validator
from datetime import datetime
from typing import Dict, List, Literal, Optional

class MessageBase(BaseModel):
    content: str

    @field_validator('content')
    @classmethod
    def validate_content(cls, v):
        if len(v) > 4000:
            raise ValueError('Message content must not exceed 4000 characters')
        return v

class MessageCreate(MessageBase):
    user_id: int
    channel_id: int
    parent_id: Optional[int] = None

class MessageSchema(MessageBase):
    id: int
    timestamp: datetime
    edited_at: Optional[datetime] = None
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
    author_profile_picture_url: Optional[str] = None

    class Config:
        from_attributes = True

class ChannelBase(BaseModel):
    name: str
    description: Optional[str] = None

class ChannelCreate(ChannelBase):
    admin_only: bool = False

    @field_validator('name')
    @classmethod
    def validate_name(cls, v):
        v = v.strip()
        if not v:
            raise ValueError('Channel name cannot be empty')
        if len(v) > 100:
            raise ValueError('Channel name must not exceed 100 characters')
        return v

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

    @field_validator('name')
    @classmethod
    def validate_name(cls, v):
        v = v.strip()
        if not v:
            raise ValueError('Voice channel name cannot be empty')
        if len(v) > 100:
            raise ValueError('Voice channel name must not exceed 100 characters')
        return v

class VoiceParticipantSchema(BaseModel):
    user_id: int
    username: str
    profile_picture_url: Optional[str] = None
    is_muted: bool = False
    is_bot: bool = False

class VoiceChannelSchema(VoiceChannelBase):
    id: int
    admin_only: bool = False
    creator_user_id: Optional[int] = None
    participants: List["VoiceParticipantSchema"] = []

    class Config:
        from_attributes = True


class UserBase(BaseModel):
    username: str

class UserCreate(UserBase):
    password: str
    email: Optional[str] = None

    @field_validator('username')
    @classmethod
    def validate_username(cls, v):
        v = v.strip()
        if len(v) < 3 or len(v) > 32:
            raise ValueError('Username must be 3-32 characters')
        if not re.match(r'^[a-zA-Z0-9_.-]+$', v):
            raise ValueError('Username can only contain letters, numbers, underscores, dots, and dashes')
        return v

    @field_validator('password')
    @classmethod
    def validate_password(cls, v):
        if len(v) < 8:
            raise ValueError('Password must be at least 8 characters')
        if len(v) > 128:
            raise ValueError('Password must be at most 128 characters')
        if not any(c.isdigit() for c in v):
            raise ValueError('Password must contain at least one number')
        if not any(c.isalpha() for c in v):
            raise ValueError('Password must contain at least one letter')
        return v

class RegisterRequest(UserCreate):
    pass

class LoginRequest(BaseModel):
    username: str
    password: str

class UserSchema(UserBase):
    id: int
    role: str
    profile_picture_url: Optional[str] = None
    email: Optional[str] = None
    is_email_verified: bool = False
    last_login_at: Optional[datetime] = None
    created_at: Optional[datetime] = None

    class Config:
        from_attributes = True

class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user: UserSchema

class RefreshRequest(BaseModel):
    refresh_token: str

class AccessTokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"

class PasswordChangeRequest(BaseModel):
    current_password: str
    new_password: str

    @field_validator('new_password')
    @classmethod
    def validate_new_password(cls, v):
        if len(v) < 8:
            raise ValueError('Password must be at least 8 characters')
        if len(v) > 128:
            raise ValueError('Password must be at most 128 characters')
        if not any(c.isdigit() for c in v):
            raise ValueError('Password must contain at least one number')
        if not any(c.isalpha() for c in v):
            raise ValueError('Password must contain at least one letter')
        return v

class PasswordResetRequest(BaseModel):
    email: str

class PasswordResetConfirm(BaseModel):
    token: str
    new_password: str

    @field_validator('new_password')
    @classmethod
    def validate_new_password(cls, v):
        if len(v) < 8:
            raise ValueError('Password must be at least 8 characters')
        if len(v) > 128:
            raise ValueError('Password must be at most 128 characters')
        if not any(c.isdigit() for c in v):
            raise ValueError('Password must contain at least one number')
        if not any(c.isalpha() for c in v):
            raise ValueError('Password must contain at least one letter')
        return v

class UserUpdate(BaseModel):
    username: Optional[str] = None
    profile_picture_url: Optional[str] = None


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


class ChannelNotificationStateSchema(BaseModel):
    channel_id: int
    latest_message_id: int
    latest_message_timestamp: datetime
    mentioned: bool = False


class ChannelReadStateUpdate(BaseModel):
    message_id: Optional[int] = None
