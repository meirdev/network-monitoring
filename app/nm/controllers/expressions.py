from fastapi import APIRouter, HTTPException, status

from nm.models.expression import Expression, ExpressionCreate, ExpressionUpdate
from nm.response import Response, encoder
from nm.services.expression import ExpressionServiceDep

router = APIRouter()


@router.get("/", response_model=Response[list[Expression]])
def get_expressions(expression_service: ExpressionServiceDep):
    expressions = expression_service.get_expressions()

    return encoder(expressions)


@router.get("/{expression_id}", response_model=Response[Expression])
def get_expression(expression_service: ExpressionServiceDep, expression_id: str):
    expression = expression_service.get_expression(expression_id)
    if expression is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)

    return encoder(expression)


@router.post("/", response_model=Response[Expression])
def add_expression(
    expression_service: ExpressionServiceDep, expression: ExpressionCreate
):
    created_expression = expression_service.add_expression(expression)

    return encoder(created_expression, status_code=status.HTTP_201_CREATED)


@router.put("/{expression_id}", response_model=Response[Expression])
def update_expression(
    expression_service: ExpressionServiceDep,
    expression_id: str,
    expression: ExpressionUpdate,
):
    updated_expression = expression_service.update_expression(expression_id, expression)

    return encoder(updated_expression)


@router.delete("/{expression_id}")
def delete_expression(expression_service: ExpressionServiceDep, expression_id: str):
    expression_service.delete_expression(expression_id)

    return encoder(None, status_code=status.HTTP_204_NO_CONTENT)
