"""Production safety checks on Settings."""

import pytest

from app.config import Settings


def test_validate_production_rejects_hexa_use_sqlite(monkeypatch):
    monkeypatch.setenv("HEXA_USE_SQLITE", "1")
    s = Settings(
        app_env="production",
        dev_return_otp=False,
        jwt_secret="x" * 64,
        jwt_refresh_secret="y" * 64,
        database_ssl_insecure=False,
    )
    with pytest.raises(RuntimeError, match="HEXA_USE_SQLITE"):
        s.validate_production_safety()


def test_validate_production_ok_when_sqlite_env_cleared(monkeypatch):
    monkeypatch.delenv("HEXA_USE_SQLITE", raising=False)
    s = Settings(
        app_env="production",
        dev_return_otp=False,
        jwt_secret="x" * 64,
        jwt_refresh_secret="y" * 64,
        database_ssl_insecure=False,
    )
    s.validate_production_safety()


def test_validate_production_rejects_short_or_same_jwt_secrets(monkeypatch):
    monkeypatch.delenv("HEXA_USE_SQLITE", raising=False)
    too_short = Settings(
        app_env="production",
        dev_return_otp=False,
        jwt_secret="x" * 32,
        jwt_refresh_secret="y" * 64,
        database_ssl_insecure=False,
    )
    with pytest.raises(RuntimeError, match="at least 48"):
        too_short.validate_production_safety()

    same = Settings(
        app_env="production",
        dev_return_otp=False,
        jwt_secret="z" * 64,
        jwt_refresh_secret="z" * 64,
        database_ssl_insecure=False,
    )
    with pytest.raises(RuntimeError, match="must be different"):
        same.validate_production_safety()
