from contextlib import asynccontextmanager
from typing import AsyncIterator

from clickhouse_driver import Client
from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError

from nm.controllers.alerts import router as alerts_router
from nm.controllers.routers import router as routers_router
from nm.controllers.rules import router as rules_router
from nm.response import ResponseError, encoder, response_error
from nm.settings import settings
from nm.state import State


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[State]:
    yield {
        "client_admin": Client(
            host=settings.clickhouse_dsn_admin.host,
            port=settings.clickhouse_dsn_admin.port,
            user=settings.clickhouse_dsn_admin.username,
            password=settings.clickhouse_dsn_admin.password,
        ),
        "client_reader": Client(
            host=settings.clickhouse_dsn_reader.host,
            port=settings.clickhouse_dsn_reader.port,
            user=settings.clickhouse_dsn_reader.username,
            password=settings.clickhouse_dsn_reader.password,
        ),
    }


app = FastAPI(
    lifespan=lifespan,
    title="Network Monitoring API",
)


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    res = response_error(
        [
            ResponseError(
                message=f"{'.'.join(err.get('loc'))}: {err.get('msg', 'error')}"
            )
            for err in exc.errors()
        ]
    )

    return encoder(
        content=res.model_dump(),
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
    )


app.include_router(routers_router, prefix="/routers", tags=["routers"])
app.include_router(rules_router, prefix="/rules", tags=["rules"])
app.include_router(alerts_router, prefix="/alerts", tags=["alerts"])
