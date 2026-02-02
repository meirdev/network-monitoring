from typing import Annotated, Any, cast

from fastapi import Depends

from nm.models.router import Router, RouterCreate, RouterUpdate
from nm.services._base import BaseService
from nm.utils import generate_id


class RouterIPExistsError(Exception):
    pass


class RouterService(BaseService):
    def get_routers(self) -> list[Router]:
        result = cast(
            list[tuple[Any, ...]],
            self.state.client_admin.execute("""
        SELECT
            id,
            name,
            router_ip,
            default_sampling
        FROM flows.routers
        """),
        )

        return [
            Router(
                id=row[0],
                name=row[1],
                router_ip=row[2],
                default_sampling=row[3],
            )
            for row in result
        ]

    def get_router(self, id: str) -> Router | None:
        result = cast(
            list[tuple[Any, ...]],
            self.state.client_admin.execute(
                """
            SELECT
                id,
                name,
                router_ip,
                default_sampling
            FROM flows.routers
            WHERE id = %(id)s
            """,
                params={"id": id},
            ),
        )
        if not result:
            return None

        row = result[0]

        return Router(
            id=row[0],
            name=row[1],
            router_ip=row[2],
            default_sampling=row[3],
        )

    def add_router(self, router: RouterCreate) -> Router:
        exists = cast(
            list[tuple[Any, ...]],
            self.state.client_admin.execute(
                "SELECT COUNT() > 0 FROM flows.routers WHERE router_ip = %(router_ip)s",
                params={"router_ip": str(router.router_ip)},
            ),
        )
        if exists and exists[0][0]:
            raise RouterIPExistsError("router IP already exists")

        id = generate_id()

        self.state.client_admin.execute(
            """
            INSERT INTO flows.routers (id, name, router_ip, default_sampling) VALUES
            """,
            [
                {
                    "id": id,
                    "name": router.name,
                    "router_ip": str(router.router_ip),
                    "default_sampling": router.default_sampling,
                }
            ],
        )

        return Router(id=id, **router.model_dump())

    def update_router(self, id: str, router: RouterUpdate) -> Router:
        exists = cast(
            list[tuple[Any, ...]],
            self.state.client_admin.execute(
                "SELECT COUNT() > 0 FROM flows.routers WHERE router_ip = %(router_ip)s AND id != %(id)s",
                params={"router_ip": str(router.router_ip), "id": id},
            ),
        )
        if exists and exists[0][0]:
            raise RouterIPExistsError("router IP already exists")

        self.state.client_admin.execute(
            """
            ALTER TABLE flows.routers UPDATE
                name = %(name)s,
                router_ip = %(router_ip)s,
                default_sampling = %(default_sampling)s
            WHERE id = %(id)s
            """,
            params={
                "id": id,
                "name": router.name,
                "router_ip": str(router.router_ip),
                "default_sampling": router.default_sampling,
            },
        )

        return Router(id=id, **router.model_dump())

    def delete_router(self, id: str) -> None:
        self.state.client_admin.execute(
            "ALTER TABLE flows.routers DELETE WHERE id = %(id)s",
            params={"id": id},
        )


RouterServiceDep = Annotated[RouterService, Depends(RouterService)]
