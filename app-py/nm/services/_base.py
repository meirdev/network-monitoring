from typing import Annotated, Any, cast

from fastapi import Depends, Request
from starlette.datastructures import State as StarletteState

from nm.state import State, StateType


def get_state(request: Request) -> StarletteState:
    return request.state


class BaseService:
    def __init__(self, state: Annotated[State, Depends(get_state)]) -> None:
        self.state: StateType = cast(StateType, StarletteState(state=cast(Any, state)))
