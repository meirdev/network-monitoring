from typing import Literal

from pydantic import BaseModel, Field, IPvAnyAddress, IPvAnyNetwork, PositiveInt


class Router(BaseModel):
    id: str | None = None
    name: str
    router_ip: IPvAnyAddress
    default_sampling: PositiveInt | None = None


class Rule(BaseModel):
    id: str | None = None
    name: str
    type: Literal["zscore", "threshold"]
    duration: Literal["1m", "5m", "10m", "15m", "20m", "30m", "45m", "60m"]
    prefixes: list[IPvAnyNetwork]
    zscore_target: Literal["bits", "packets"] | None = None
    threshold_bandwidth: PositiveInt | None = None
    threshold_packet: PositiveInt | None = None


class Monitoring(BaseModel):
    src_address: IPvAnyAddress | None = Field(default=None, alias="src-address")
    dst_address: IPvAnyAddress | None = Field(default=None, alias="dst-address")
    src_port: PositiveInt | None = Field(default=None, alias="src-port")
    dst_port: PositiveInt | None = Field(default=None, alias="dst-port")
    protocol: str
    ip_version: Literal["IPv4", "IPv6"] | None = Field(default=None, alias="ip-version")
    time_window: PositiveInt | None = Field(default=None, alias="time-window")
