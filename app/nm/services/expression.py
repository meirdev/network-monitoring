from typing import Annotated, Any, cast

from fastapi import Depends

from nm.models.expression import Expression, ExpressionCreate, ExpressionUpdate
from nm.services._base import BaseService
from nm.utils import generate_id


class ExpressionService(BaseService):
    def get_expressions(self) -> list[Expression]:
        result = cast(
            list[tuple[Any, ...]],
            self.state.client_admin.execute("""
        SELECT
            id,
            name,
            expression
        FROM flows.expressions
        """),
        )

        return [
            Expression(
                id=row[0],
                name=row[1],
                expression=row[2],
            )
            for row in result
        ]

    def get_expression(self, id: str) -> Expression | None:
        result = cast(
            list[tuple[Any, ...]],
            self.state.client_admin.execute(
                """
            SELECT
                id,
                name,
                expression
            FROM flows.expressions
            WHERE id = %(id)s
            """,
                params={"id": id},
            ),
        )
        if not result:
            return None

        row = result[0]

        return Expression(
            id=row[0],
            name=row[1],
            expression=row[2],
        )

    def add_expression(self, expression: ExpressionCreate) -> Expression:
        id = generate_id()

        self.state.client_admin.execute(
            """
            INSERT INTO flows.expressions (id, name, expression) VALUES
            """,
            [
                {
                    "id": id,
                    "name": expression.name,
                    "expression": expression.expression,
                }
            ],
        )

        return Expression(id=id, **expression.model_dump())

    def update_expression(self, id: str, expression: ExpressionUpdate) -> Expression:
        self.state.client_admin.execute(
            """
            ALTER TABLE flows.expressions UPDATE
                name = %(name)s,
                expression = %(expression)s
            WHERE id = %(id)s
            """,
            params={
                "id": id,
                "name": expression.name,
                "expression": expression.expression,
            },
        )

        return Expression(id=id, **expression.model_dump())

    def delete_expression(self, id: str) -> None:
        self.state.client_admin.execute(
            "ALTER TABLE flows.expressions DELETE WHERE id = %(id)s",
            params={"id": id},
        )
        self.state.client_admin.execute(
            "OPTIMIZE TABLE flows.expressions FINAL",
        )


ExpressionServiceDep = Annotated[ExpressionService, Depends(ExpressionService)]
