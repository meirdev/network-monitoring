from fastapi import APIRouter, HTTPException, status

from nm.models.rule import Rule, RuleCreate, RuleUpdate
from nm.response import Response, encoder
from nm.services.rule import RuleServiceDep

router = APIRouter()


@router.get("/", response_model=Response[list[Rule]])
def get_rules(rule_service: RuleServiceDep):
    rules = rule_service.get_rules()

    return encoder(rules)


@router.get("/{rule_id}", response_model=Response[Rule])
def get_rule(rule_service: RuleServiceDep, rule_id: str):
    rule = rule_service.get_rule(rule_id)
    if rule is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)

    return encoder(rule)


@router.post("/", response_model=Response[Rule], status_code=status.HTTP_201_CREATED)
def add_rule(rule_service: RuleServiceDep, rule: RuleCreate):
    created_rule = rule_service.add_rule(rule)

    return encoder(created_rule)


@router.put("/{rule_id}", response_model=Response[Rule])
def update_rule(rule_service: RuleServiceDep, rule_id: str, rule: RuleUpdate):
    updated_rule = rule_service.update_rule(rule_id, rule)

    return encoder(updated_rule)


@router.delete("/{rule_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_rule(rule_service: RuleServiceDep, rule_id: str):
    rule_service.delete_rule(rule_id)
