from typing import Annotated, cast

from fastapi import Depends, Request
from starlette.datastructures import State as StarletteState

from nm.state import State, StateType


def get_state(request: Request) -> StarletteState:
    return request.state


class BaseService:
    def __init__(self, state: Annotated[State, Depends(get_state)]) -> None:
        # in case the state is not a StarletteState (called directly without going through FastAPI),
        # we wrap it in a StarletteState.
        if not isinstance(state, StarletteState):
            state = StarletteState(state=state)  # type: ignore

        self.state: StateType = cast(StateType, state)
