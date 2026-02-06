import clickhouse_driver
import pytest
from testcontainers.clickhouse import ClickHouseContainer


@pytest.fixture(scope="module")
def test_db():
    with ClickHouseContainer("clickhouse/clickhouse-server:25.10") as clickhouse:
        client = clickhouse_driver.Client.from_url(clickhouse.get_connection_url())

        yield client
