from fastapi import APIRouter, HTTPException, status

from nm.models.router import Router, RouterCreate, RouterUpdate
from nm.response import Response, encoder
from nm.services.router import RouterIPExistsError, RouterServiceDep

router = APIRouter()


@router.get("/", response_model=Response[list[Router]])
def get_routers(router_service: RouterServiceDep):
    routers = router_service.get_routers()

    return encoder(routers)


@router.get("/{router_id}", response_model=Response[Router])
def get_router(router_service: RouterServiceDep, router_id: str):
    router = router_service.get_router(router_id)
    if router is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)

    return encoder(router)


@router.post("/", response_model=Response[Router])
def add_router(router_service: RouterServiceDep, router: RouterCreate):
    try:
        created_router = router_service.add_router(router)
    except RouterIPExistsError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Router with the same IP already exists",
        )

    return encoder(created_router, status_code=status.HTTP_201_CREATED)


@router.put("/{router_id}", response_model=Response[Router])
def update_router(
    router_service: RouterServiceDep, router_id: str, router: RouterUpdate
):
    try:
        updated_router = router_service.update_router(router_id, router)
    except RouterIPExistsError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Router with the same IP already exists",
        )

    return encoder(updated_router)


@router.delete("/{router_id}")
def delete_router(router_service: RouterServiceDep, router_id: str):
    router_service.delete_router(router_id)

    return encoder(None, status_code=status.HTTP_204_NO_CONTENT)
