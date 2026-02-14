from pydantic.fields import Field
from pydantic import ClickHouseDsn
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="allow")

    clickhouse_dsn_admin: ClickHouseDsn = Field(..., env="CLICKHOUSE_DSN_ADMIN")
    clickhouse_dsn_reader: ClickHouseDsn = Field(..., env="CLICKHOUSE_DSN_READER")


settings = Settings()
