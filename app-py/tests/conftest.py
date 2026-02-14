from pathlib import Path

import clickhouse_driver
import pytest
import sqlparse
from pydantic import ClickHouseDsn
from testcontainers.clickhouse import ClickHouseContainer

from nm.settings import settings

INIT_DB = Path(__file__).parent.parent.parent / "clickhouse" / "initdb.d"


@pytest.fixture(scope="module")
def test_db():
    with ClickHouseContainer(
        "clickhouse/clickhouse-server:25.10", username="default", password="password"
    ).with_env("CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT", "1") as clickhouse:
        client = clickhouse_driver.Client.from_url(clickhouse.get_connection_url())

        settings.clickhouse_dsn_admin = ClickHouseDsn(clickhouse.get_connection_url())
        settings.clickhouse_dsn_reader = ClickHouseDsn(clickhouse.get_connection_url())

        for sql_file in sorted(INIT_DB.glob("*.sql")):
            with open(sql_file) as f:
                statements = sqlparse.split(f.read())
                for statement in statements:
                    client.execute(statement)

        yield client
