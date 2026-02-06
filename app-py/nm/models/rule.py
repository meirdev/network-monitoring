from typing import Literal

from pydantic import BaseModel, Field, IPvAnyNetwork


class RuleBase(BaseModel):
    name: str = Field(max_length=256)
    prefixes: list[IPvAnyNetwork] = Field(min_length=1)
    type: Literal["threshold", "zscore", "advanced_ddos"]
    bandwidth_threshold: int | None = Field(default=None, ge=1)
    packet_threshold: int | None = Field(default=None, ge=1)
    duration: int | None = Field(default=None, ge=1)
    zscore_sensitivity: Literal["low", "medium", "high"] | None = None
    zscore_target: Literal["bits", "packets"] | None = None

    @property
    def prefixes_str(self) -> list[str]:
        return [str(i) for i in self.prefixes]


class RuleCreate(RuleBase):
    pass


class RuleUpdate(RuleBase):
    pass


class Rule(RuleBase):
    id: str
