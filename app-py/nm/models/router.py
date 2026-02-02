from pydantic import BaseModel, Field, IPvAnyAddress


class RouterBase(BaseModel):
    name: str
    router_ip: IPvAnyAddress
    default_sampling: int = Field(ge=0)


class RouterCreate(RouterBase):
    pass


class RouterUpdate(RouterBase):
    pass


class Router(RouterBase):
    id: str
