from typing import Annotated, Any, cast

from fastapi import Depends

from nm.models.rule import Rule, RuleCreate, RuleUpdate
from nm.services._base import BaseService
from nm.utils import generate_id


class RuleService(BaseService):
    def get_rules(self) -> list[Rule]:
        result = cast(list[tuple[Any, ...]], self.state.client_admin.execute("""
        SELECT
            id,
            name,
            prefixes,
            type,
            bandwidth_threshold,
            packet_threshold,
            duration,
            zscore_sensitivity,
            zscore_target
        FROM flows.rules
        """))

        return [
            Rule(
                id=row[0],
                name=row[1],
                prefixes=row[2],
                type=row[3],
                bandwidth_threshold=row[4],
                packet_threshold=row[5],
                duration=row[6],
                zscore_sensitivity=row[7],
                zscore_target=row[8],
            )
            for row in result
        ]

    def get_rule(self, id: str) -> Rule | None:
        result = cast(list[tuple[Any, ...]], self.state.client_admin.execute(
            """
        SELECT
            id,
            name,
            prefixes,
            type,
            bandwidth_threshold,
            packet_threshold,
            duration,
            zscore_sensitivity,
            zscore_target
        FROM flows.rules
        WHERE id = %(id)s
        """,
            params={"id": id},
        ))
        if not result:
            return None

        row = result[0]

        return Rule(
            id=row[0],
            name=row[1],
            prefixes=row[2],
            type=row[3],
            bandwidth_threshold=row[4],
            packet_threshold=row[5],
            duration=row[6],
            zscore_sensitivity=row[7],
            zscore_target=row[8],
        )

    def add_rule(self, rule: RuleCreate) -> Rule:
        id = generate_id()

        self.state.client_admin.execute(
            """
            INSERT INTO flows.rules (
                id,
                name,
                prefixes,
                type,
                bandwidth_threshold,
                packet_threshold,
                duration,
                zscore_sensitivity,
                zscore_target
            ) VALUES
            """,
            [
                {
                    "id": id,
                    "name": rule.name,
                    "prefixes": rule.prefixes_str,
                    "type": rule.type,
                    "bandwidth_threshold": rule.bandwidth_threshold,
                    "packet_threshold": rule.packet_threshold,
                    "duration": rule.duration,
                    "zscore_sensitivity": rule.zscore_sensitivity,
                    "zscore_target": rule.zscore_target,
                }
            ],
        )
        self._update_dictionary()

        return Rule(id=id, **rule.model_dump())

    def update_rule(self, id: str, rule: RuleUpdate) -> Rule:
        self.state.client_admin.execute(
            """
            ALTER TABLE flows.rules UPDATE
                name = %(name)s,
                prefixes = %(prefixes)s,
                type = %(type)s,
                bandwidth_threshold = %(bandwidth_threshold)s,
                packet_threshold = %(packet_threshold)s,
                duration = %(duration)s,
                zscore_sensitivity = %(zscore_sensitivity)s,
                zscore_target = %(zscore_target)s
            WHERE id = %(id)s
            """,
            params={
                "id": id,
                "name": rule.name,
                "prefixes": rule.prefixes_str,
                "type": rule.type,
                "bandwidth_threshold": rule.bandwidth_threshold,
                "packet_threshold": rule.packet_threshold,
                "duration": rule.duration,
                "zscore_sensitivity": rule.zscore_sensitivity,
                "zscore_target": rule.zscore_target,
            },
        )
        self._update_dictionary()

        return Rule(id=id, **rule.model_dump())

    def delete_rule(self, id: str) -> None:
        self.state.client_admin.execute(
            "ALTER TABLE flows.rules DELETE WHERE id = %(id)s",
            params={"id": id},
        )
        self._update_dictionary()

    def _update_dictionary(self) -> None:
        self.state.client_admin.execute("SYSTEM RELOAD DICTIONARY flows.prefixes")


RuleServiceDep = Annotated[RuleService, Depends(RuleService)]
