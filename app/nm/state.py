from typing import TypedDict

from clickhouse_driver import Client


class State(TypedDict):
    client_admin: Client
    client_reader: Client


class StateType:
    client_admin: Client
    client_reader: Client
