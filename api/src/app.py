import contextlib
from typing import Annotated, AsyncIterator, TypedDict

import asyncpg
import clickhouse_connect
import clickhouse_connect.driver.asyncclient as clickhouse_connect_async
from fastapi import Depends, FastAPI, HTTPException

from src.dto import Router, Rule
from src.settings import settings

type Connection = asyncpg.pool.PoolConnectionProxy[asyncpg.Record]

type ClickHouseClient = clickhouse_connect_async.AsyncClient


class AppExtra(TypedDict):
    postgres_client: asyncpg.Pool[asyncpg.Record]
    clickhouse_client: ClickHouseClient


class App(FastAPI):
    extra: AppExtra


@contextlib.asynccontextmanager
async def lifespan(app: FastAPI):
    pg_dsn = settings.pg_dsn.unicode_string()
    ch_dsn = settings.ch_dsn.unicode_string()

    clickhouse_async_client = await clickhouse_connect.get_async_client(dsn=ch_dsn)

    async with (
        asyncpg.create_pool(pg_dsn) as pool,
        clickhouse_async_client as ch_client,
    ):
        app.extra["postgres_client"] = pool
        app.extra["clickhouse_client"] = ch_client

        yield


async def get_session() -> AsyncIterator[Connection]:
    async with app.extra["postgres_client"].acquire() as connection:
        yield connection


type Session = Annotated[Connection, Depends(get_session)]

type ClickHouse = Annotated[
    ClickHouseClient, Depends(lambda: app.extra["clickhouse_client"])
]


app = App(lifespan=lifespan)


@app.get("/health", tags=["health"])
async def health():
    return {"status": "ok"}


@app.get("/routers", tags=["routers"])
async def list_routers(session: Session):
    records = await session.fetch("SELECT * FROM routers")

    return map(dict, records)


@app.get("/routers/{router_id}", tags=["routers"])
async def get_router(session: Session, router_id: str):
    record = await session.fetchrow("SELECT * FROM routers WHERE id = $1", router_id)

    return record


@app.post("/routers/{router_id}", tags=["routers"])
async def create_router(session: Session, data: Router):
    result = await session.execute(
        """INSERT INTO routers (name, router_ip, default_sampling) VALUES ($1, $2, $3) RETURNING *""",
        data.name,
        data.router_ip,
        data.default_sampling,
    )

    return result


@app.put("/routers/{router_id}", tags=["routers"])
async def update_router(session: Session, router_id: str, data: Router):
    result = await session.execute(
        """UPDATE routers SET name = $1, router_ip = $2, default_sampling = $3 WHERE id = $4 RETURNING *""",
        data.name,
        data.router_ip,
        data.default_sampling,
        router_id,
    )

    return result


@app.delete("/routers/{router_id}", tags=["routers"])
async def delete_router(session: Session, router_id: str):
    await session.execute("DELETE FROM routers WHERE id = $1", router_id)


@app.get("/rules", tags=["rules"])
async def list_rules(session: Session):
    records = await session.fetch("SELECT * FROM rules")

    return map(dict, records)


@app.get("/rules/{rule_id}", tags=["rules"])
async def get_rule(session: Session, rule_id: str):
    record = await session.fetchrow("SELECT * FROM rules WHERE id = $1", rule_id)
    if not record:
        raise HTTPException(status_code=404, detail="Rule not found")

    return record


@app.post("/rules", tags=["rules"])
async def create_rule(session: Session, data: Rule):
    await session.execute(
        """INSERT INTO rules (name, type, duration, prefixes, zscore_target, threshold_bandwidth, threshold_packet) VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *""",
        data.name,
        data.type,
        data.duration,
        data.prefixes,
        data.zscore_target,
        data.threshold_bandwidth,
        data.threshold_packet,
    )


@app.put("/rules/{rule_id}", tags=["rules"])
async def update_rule(session: Session, rule_id: str, data: Rule):
    await session.execute(
        """UPDATE rules SET name = $1, type = $2, duration = $3, prefixes = $4, zscore_target = $5, threshold_bandwidth = $6, threshold_packet = $7 WHERE id = $8 RETURNING *""",
        data.name,
        data.type,
        data.duration,
        data.prefixes,
        data.zscore_target,
        data.threshold_bandwidth,
        data.threshold_packet,
        rule_id,
    )


@app.delete("/rules/{rule_id}", tags=["rules"])
async def delete_rule(session: Session, rule_id: str):
    await session.execute("DELETE FROM rules WHERE id = $1", rule_id)


@app.get("/monitoring", tags=["monitoring"])
async def monitoring(clickhouse: ClickHouse):
    await clickhouse.query_df(
        """
        SELECT
            *
        FROM
            flows
        """
    )
