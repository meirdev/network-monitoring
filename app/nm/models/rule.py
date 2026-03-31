from typing import Literal

from pydantic import (
    BaseModel,
    Field,
    IPvAnyNetwork,
    model_validator,
)


class RuleBase(BaseModel):
    name: str = Field(max_length=256)
    prefixes: list[IPvAnyNetwork] = Field(min_length=1)
    type: Literal["threshold", "zscore"]
    bandwidth_threshold: int | None = Field(
        default=None, ge=1, description="Bandwidth threshold in bits per second"
    )
    packet_threshold: int | None = Field(
        default=None, ge=1, description="Packet threshold in packets per second"
    )
    duration: Literal[1, 5, 10, 15, 20, 30, 45, 60] | None = Field(
        default=None, description="Duration in minutes"
    )
    zscore_sensitivity: Literal["low", "medium", "high"] | None = None
    zscore_target: Literal["bits", "packets"] | None = None

    @model_validator(mode="after")
    def validate_fields_for_type(self):
        if self.type == "threshold":
            if self.duration is None:
                raise ValueError("threshold rules require 'duration'")
            if self.bandwidth_threshold is None and self.packet_threshold is None:
                raise ValueError(
                    "threshold rules require 'bandwidth_threshold' or 'packet_threshold'"
                )
        elif self.type == "zscore":
            if self.zscore_sensitivity is None:
                raise ValueError("zscore rules require 'zscore_sensitivity'")
            if self.zscore_target is None:
                raise ValueError("zscore rules require 'zscore_target'")
        return self

    @property
    def prefixes_str(self) -> list[str]:
        return [str(i) for i in self.prefixes]


class RuleCreate(RuleBase):
    pass


class RuleUpdate(RuleBase):
    pass


class Rule(RuleBase):
    id: str
