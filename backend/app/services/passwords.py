"""Bcrypt password hashing."""

import bcrypt
import re

_COMMON_PASSWORDS = {
    "password",
    "password123",
    "qwerty123",
    "admin123",
    "12345678",
    "123456789",
    "letmein",
    "welcome123",
}


def validate_password_strength(plain: str) -> None:
    pwd = (plain or "").strip()
    if len(pwd) < 8:
        raise ValueError("Password must be at least 8 characters")
    if not re.search(r"\d", pwd):
        raise ValueError("Password must include at least one number")
    if pwd.lower() in _COMMON_PASSWORDS:
        raise ValueError("Choose a stronger password")


def hash_password(plain: str) -> str:
    validate_password_strength(plain)
    return bcrypt.hashpw(plain.encode("utf-8"), bcrypt.gensalt()).decode("ascii")


def verify_password(plain: str, password_hash: str) -> bool:
    try:
        return bcrypt.checkpw(plain.encode("utf-8"), password_hash.encode("ascii"))
    except ValueError:
        return False
