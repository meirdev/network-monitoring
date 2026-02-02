from typing import Any, Generic, TypeVar

import orjson
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from pydantic.json import pydantic_encoder

T = TypeVar("T")


class ResponseError(BaseModel):
    message: str


class Response(BaseModel, Generic[T]):
    result: T | None = None
    errors: list[ResponseError] = Field(default_factory=list)
    success: bool


def response_success(result: T) -> Response[T]:
    return Response(result=result, success=True)


def response_error(errors) -> Response[None]:
    return Response(result=None, errors=errors, success=False)


class encoder(JSONResponse):
    def render(self, content: Any) -> bytes:
        content = response_success(content)

        return orjson.dumps(
            content,
            default=pydantic_encoder,
            option=orjson.OPT_NON_STR_KEYS | orjson.OPT_SERIALIZE_NUMPY,
        )
