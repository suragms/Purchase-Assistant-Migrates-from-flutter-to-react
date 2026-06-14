import os
from functools import lru_cache

from pydantic import AliasChoices, Field
from pydantic_settings import (
    BaseSettings,
    PydanticBaseSettingsSource,
    SettingsConfigDict,
)


class Settings(BaseSettings):
    """Runtime configuration. Environment variable names match [.env.example](../../.env.example)."""

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    @classmethod
    def settings_customise_sources(
        cls,
        settings_cls: type[BaseSettings],
        init_settings: PydanticBaseSettingsSource,
        env_settings: PydanticBaseSettingsSource,
        dotenv_settings: PydanticBaseSettingsSource,
        file_secret_settings: PydanticBaseSettingsSource,
    ) -> tuple[PydanticBaseSettingsSource, ...]:
        """Prefer `backend/.env` for local dev; process env always wins over `.env` (last source)."""
        if os.environ.get("APP_ENV", "").lower() == "test":
            # Under pytest, `conftest.py` sets env vars (DATABASE_URL, HEXA_USE_SQLITE, …)
            # that MUST beat the developer's `backend/.env` — otherwise tests run against
            # the real dev DB and fail with mysterious schema mismatches.
            return (
                init_settings,
                env_settings,
                dotenv_settings,
                file_secret_settings,
            )
        return (
            init_settings,
            dotenv_settings,
            env_settings,
            file_secret_settings,
        )

    app_env: str = "development"
    app_name: str = "hexa-purchase-assistant"
    app_url: str = "http://localhost:8000"
    admin_url: str = "http://localhost:5173"
    cors_origins: str = (
        "http://localhost:5173,http://127.0.0.1:5173,"
        "http://localhost:5174,http://127.0.0.1:5174,"
        "http://localhost:5175,http://127.0.0.1:5175,"
        "http://localhost:3000,http://127.0.0.1:3000,"
        "http://localhost:8080,http://127.0.0.1:8080,"
        "http://localhost:8081,http://127.0.0.1:8081,"
        "http://localhost:8082,http://127.0.0.1:8082,"
        "http://localhost:8090,http://127.0.0.1:8090,"
        "http://localhost:8091,http://127.0.0.1:8091,"
        "http://localhost:8092,http://127.0.0.1:8092"
    )

    # Local dev without Postgres: sqlite+aiosqlite:///./hexa_dev.db (file created next to cwd when running uvicorn from backend/)
    database_url: str = "postgresql+asyncpg://user:password@localhost:5432/hexa"
    # Optional: Supabase pooler (Session or Transaction) from Dashboard → Connect → pooler URI, port 6543.
    # On some hosts (e.g. Render) direct db.<ref>.supabase.co:5432 can fail with "Network is unreachable";
    # set this to the pooler URL and keep DATABASE_URL as fallback or duplicate — engine uses this when set.
    database_pooler_url: str | None = None
    # When set, overrides any password embedded in DATABASE_POOLER_URL. Use with a URI that has no
    # password in the userinfo (postgresql+asyncpg://USER@HOST:PORT/DB) so special chars like @ in the
    # password do not break parsing (avoids gaierror / "Name or service not known" on Render).
    database_pooler_password: str | None = None
    # Dev-only: if TLS fails with CERTIFICATE_VERIFY_FAILED (AV/corporate proxy MITM), set true. Forbidden in production.
    database_ssl_insecure: bool = False
    # Encrypted TLS to Postgres, but skip verifying the server certificate chain. Some PaaS (e.g. Render) + Supabase
    # pooler combinations fail SSL verify despite valid AWS certs; opt-in only. Prefer false once CA trust works.
    database_ssl_skip_verify: bool = False
    # Async SQLAlchemy QueuePool knobs (PostgreSQL only; SQLite ignores).
    database_pool_size: int = Field(
        default=10,
        validation_alias=AliasChoices("DATABASE_POOL_SIZE", "DB_POOL_SIZE"),
    )
    database_pool_max_overflow: int = Field(
        default=15,
        validation_alias=AliasChoices("DATABASE_MAX_OVERFLOW", "DB_MAX_OVERFLOW"),
    )
    database_pool_timeout_seconds: int = Field(
        default=15,
        validation_alias=AliasChoices("DATABASE_POOL_TIMEOUT", "DB_POOL_TIMEOUT"),
    )
    database_pool_recycle_seconds: int = 300
    # asyncpg statement timeout per executed command (seconds). 0 disables.
    database_command_timeout_seconds: float = Field(
        default=45.0,
        validation_alias=AliasChoices("DATABASE_COMMAND_TIMEOUT", "DB_CMD_TIMEOUT"),
    )
    # Initial connect handshake timeout already used in database.py connect_args timeout (legacy).
    database_connect_timeout_seconds: float = Field(
        default=15.0,
        validation_alias=AliasChoices("DATABASE_CONNECT_TIMEOUT", "DB_CONNECT_TIMEOUT"),
    )
    # Emit WARNING when a SQL round-trip exceeds this many ms on sync mirror engine. 0 disables.
    database_slow_query_log_ms: int = 100
    # GET-only degradation: SQLAlchemy may use default empty JSON for catastrophic reads (middleware).
    database_get_read_failsafe: bool = True
    # asyncio wait_for cap for curated heavy GET aggregates (snapshot, home-overview, month dashboard).
    # 0 disables. Mutations rely on database_command_timeout_seconds instead.
    # 8s default: Render cold home-overview can exceed 4s; home-overview also uses 10s override.
    api_read_budget_seconds: float = 8.0

    # Log WARNING when HTTP round-trip exceeds this many ms (all routes). 0 disables slow-request WARN.
    http_slow_request_warning_ms: int = 500
    # Echo X-Request-Id through responses (reuse client-supplied UUID or allocate one).
    http_propagate_request_id: bool = True
    # Structured HTTP_JSON on every request (noisy on Render; keep false in production).
    http_access_log_all: bool = False

    redis_url: str | None = "redis://localhost:6379/0"

    jwt_secret: str = "change-me-min-32-chars-dev-only"
    jwt_refresh_secret: str = "change-me-min-32-chars-refresh-dev"
    jwt_access_ttl_minutes: int = 15
    jwt_refresh_ttl_days: int = 30

    dev_return_otp: bool = True
    dev_otp_code: str = "000000"

    otp_provider: str = "twilio"
    otp_api_key: str | None = None
    otp_sender_id: str = "HEXA"
    otp_requests_per_minute_per_ip: int = 10

    superadmin_bootstrap_phone: str | None = None  # legacy; prefer SUPERADMIN_BOOTSTRAP_EMAIL
    superadmin_bootstrap_email: str | None = None
    allow_public_registration: bool = Field(
        default=False,
        validation_alias=AliasChoices("ALLOW_PUBLIC_REGISTRATION"),
    )

    # Comma-separated OAuth 2.0 client IDs whose ID tokens we accept (usually one Web client used as serverClientId in Flutter).
    google_oauth_client_ids: str = ""

    # Legacy BSP fields — super-admin platform integration / forks. Harisree app assistant uses /ai/chat only.
    dialog360_api_key: str | None = None
    dialog360_base_url: str = "https://waba-v2.360dialog.io"
    dialog360_phone_number_id: str | None = None
    dialog360_webhook_secret: str | None = None
    dialog360_template_namespace: str | None = None

    # Optional: Authkey.io WhatsApp (outbound). If set, outbound text may route here instead of 360dialog.
    authkey_api_key: str | None = None
    authkey_base_url: str = "https://manage.authkey.io"
    authkey_sender_label: str = "HARISREE"
    authkey_from_number: str | None = None
    # E.164 number to show in the app (“chat with this assistant”). Falls back to authkey_from_number if unset.
    whatsapp_assistant_e164: str | None = None

    openai_api_key: str | None = None
    openai_model_parse: str = Field(
        default="gpt-4.1-mini",
        validation_alias=AliasChoices("OPENAI_MODEL_PARSE", "OPENAI_MODEL"),
    )
    openai_model_summary: str = "gpt-4.1-mini"
    openai_timeout_ms: int = Field(default=60000, ge=1000, le=180000)
    enable_vision: bool = True
    enable_ai_extraction: bool = True
    # stub | openai | groq | gemini — intent extraction uses matching key (env or platform_integration DB).
    ai_provider: str = "stub"
    # Second LLM call for WhatsApp *query* replies: rephrase server-computed FACTS (adds API cost).
    whatsapp_llm_reply: bool = False
    # Broader agent polish: previews, save/update acks, clarify/help (adds API cost per message when enabled).
    whatsapp_llm_agent: bool = False
    # Optional shared secret: Authkey must send header X-Authkey-Webhook-Secret matching this value (empty = disabled).
    authkey_webhook_secret: str | None = None
    # Inbound Authkey webhook rate limits (per phone; in-process — use Redis + single worker or tune for multi-instance).
    webhook_max_per_minute: int = 20
    webhook_max_per_hour: int = 120
    groq_model: str = "llama-3.3-70b-versatile"
    gemini_model: str = "gemini-2.0-flash"
    groq_api_key: str | None = None
    google_ai_api_key: str | None = None
    ocr_provider: str = "google_vision"
    ocr_api_key: str | None = None
    stt_provider: str = "openai_whisper"
    stt_api_key: str | None = None

    s3_bucket: str | None = None
    s3_region: str = "ap-south-1"
    s3_access_key: str | None = None
    s3_secret_key: str | None = None
    s3_endpoint: str | None = None

    razorpay_key_id: str | None = None
    razorpay_key_secret: str | None = None
    razorpay_webhook_secret: str | None = None
    plan_basic_price_inr: int = 49900
    plan_pro_price_inr: int = 99900
    plan_premium_price_inr: int = 199900
    # When true, WhatsApp/AI routes check BusinessSubscription (grandfather: no row = allowed).
    billing_enforce: bool = False
    # Default bundle pricing hints (paise): base cloud + optional WhatsApp+AI add-on (admin can override per business).
    billing_cloud_infra_paise: int = 230_000  # ₹2,300 (paise)
    billing_whatsapp_ai_addon_paise: int = 250_000  # ₹2,500 (paise)

    sentry_dsn: str | None = None
    log_level: str = "INFO"
    metrics_token: str | None = None
    # Optional static Bearer for admin API + admin_web (machine auth). Prefer long random values in production.
    admin_api_token: str | None = None
    # Internal admin SPA login (POST /v1/admin/login). Plaintext — use only on trusted networks.
    admin_email: str | None = None
    admin_password: str | None = None

    enable_ai: bool = True
    enable_ocr: bool = False

    # WhatsApp Cloud API (server-side scheduled auto-send; optional)
    whatsapp_cloud_access_token: str | None = None
    whatsapp_cloud_phone_number_id: str | None = None
    # Secret for Render cron → internal sender endpoint (set long random value in production)
    whatsapp_reports_cron_secret: str | None = None
    enable_voice: bool = False
    enable_realtime: bool = True

    trusted_hosts: str | None = None
    # Optional: override seed JSON location (default: <repo>/data/files, else backend/scripts/data).
    # Same as env SEED_DATA_DIR. Used by POST /v1/me/bootstrap-workspace and seed scripts.
    seed_data_dir: str | None = None

    def google_oauth_client_id_list(self) -> list[str]:
        return [x.strip() for x in self.google_oauth_client_ids.split(",") if x.strip()]

    def validate_production_safety(self) -> None:
        """Call on startup when app_env is production."""
        if self.app_env.lower() != "production":
            return
        if self.dev_return_otp:
            raise RuntimeError("DEV_RETURN_OTP must be false in production")
        if "change-me" in self.jwt_secret.lower() or "change-me" in self.jwt_refresh_secret.lower():
            raise RuntimeError("JWT secrets must be changed in production")
        if len(self.jwt_secret) < 32 or len(self.jwt_refresh_secret) < 32:
            raise RuntimeError("JWT secrets must be at least 32 characters in production")
        if self.database_ssl_insecure:
            raise RuntimeError("DATABASE_SSL_INSECURE must be false in production")


@lru_cache
def get_settings() -> Settings:
    return Settings()
