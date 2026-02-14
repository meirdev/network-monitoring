from typing import cast

from clickhouse_driver import Client


def test_is_working(test_db: Client):
    result = cast(list, test_db.execute("SELECT 1"))

    assert result[0][0] == 1
