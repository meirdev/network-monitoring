from pydantic import ClickHouseDsn, PostgresDsn
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    pg_dsn: PostgresDsn
    ch_dsn: ClickHouseDsn


settings = Settings() # type: ignore
