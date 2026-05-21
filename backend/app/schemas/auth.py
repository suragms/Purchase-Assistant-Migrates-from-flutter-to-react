import re

from pydantic import BaseModel, Field, field_validator


class RegisterRequest(BaseModel):
    email: str = Field(..., min_length=5, max_length=320)
    username: str = Field(..., min_length=3, max_length=64)
    password: str = Field(..., min_length=8, max_length=128)
    name: str | None = Field(
        None, max_length=255, description="Optional display name; stored as users.name"
    )

    @field_validator("email")
    @classmethod
    def email_lower(cls, v: str) -> str:
        return v.strip().lower()

    @field_validator("username")
    @classmethod
    def username_normalize(cls, v: str) -> str:
        s = v.strip().lower()
        if not re.match(r"^[a-z0-9_]{3,64}$", s):
            raise ValueError("Username: 3–64 chars, letters, numbers, underscore only")
        return s

    @field_validator("name")
    @classmethod
    def name_strip(cls, v: str | None) -> str | None:
        if v is None:
            return None
        t = v.strip()
        return t if t else None


class LoginRequest(BaseModel):
    """Log in with username, phone, or email plus password."""

    identifier: str = Field(..., min_length=3, max_length=320)
    password: str = Field(..., min_length=1, max_length=128)

    @field_validator("identifier")
    @classmethod
    def identifier_strip(cls, v: str) -> str:
        return v.strip()


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    expires_in: int


class GoogleAuthRequest(BaseModel):
    """ID token from Google Sign-In (Flutter `GoogleSignInAuthentication.idToken`)."""

    id_token: str = Field(..., min_length=20, max_length=12000)


class RefreshRequest(BaseModel):
    refresh_token: str


class ForgotPasswordRequest(BaseModel):
    """Request password reset; response is uniform whether or not the email exists."""

    email: str = Field(..., min_length=3, max_length=320)

    @field_validator("email")
    @classmethod
    def email_lower(cls, v: str) -> str:
        return v.strip().lower()


class ResetPasswordRequest(BaseModel):
    """Complete reset using the token from the email link (or dev log)."""

    token: str = Field(..., min_length=10, max_length=2000)
    new_password: str = Field(..., min_length=8, max_length=128)
