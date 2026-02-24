from pydantic import BaseModel


class ExpressionBase(BaseModel):
    name: str
    expression: str


class ExpressionCreate(ExpressionBase):
    pass


class ExpressionUpdate(ExpressionBase):
    pass


class Expression(ExpressionBase):
    id: str
