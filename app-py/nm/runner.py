import logging
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor

import schedule
from clickhouse_driver import Client

from nm.services.alert import AlertService
from nm.settings import settings

logger = logging.getLogger(__file__)

logging.basicConfig(stream=sys.stdout, level=logging.DEBUG)

clients: dict[int, Client] = {}


def foo():
    ident = threading.get_ident()

    client = clients.get(ident)

    if client is None:
        logger.info("New client")

        client = Client(
            host=settings.clickhouse_dsn_admin.host,
            user=settings.clickhouse_dsn_admin.username,
            password=settings.clickhouse_dsn_admin.password,
        )

        clients[ident] = client

    alert_service = AlertService(
        state={"client_admin": client, "client_reader": client}
    )

    logger.info("Get threshold alerts")

    print(alert_service.get_threshold_alerts())
    print(alert_service.get_ddos_alerts())


def main():
    with ThreadPoolExecutor() as executor:
        schedule.every(10).seconds.do(executor.submit, foo)

        while True:
            schedule.run_pending()
            time.sleep(1)


if __name__ == "__main__":
    main()
