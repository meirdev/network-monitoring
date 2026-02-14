from pydantic import ClickHouseDsn
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="allow")

    clickhouse_dsn_admin: ClickHouseDsn
    clickhouse_dsn_reader: ClickHouseDsn


settings = Settings()
