from clickhouse_driver import Client
from fastapi.testclient import TestClient

from nm.main import app


def test_create_router(test_db: Client):
    with TestClient(app) as client:
        response = client.post(
            "/routers/",
            json={
                "name": "Router 1",
                "router_ip": "192.168.1.1",
                "default_sampling": 100,
            },
        )
        assert response.status_code == 201

        data = response.json()

        assert data["success"] is True
        assert data["result"]["name"] == "Router 1"
        assert data["result"]["router_ip"] == "192.168.1.1"
        assert data["result"]["default_sampling"] == 100
        assert "id" in data["result"]


def test_get_routers(test_db: Client):
    with TestClient(app) as client:
        client.post(
            "/routers/",
            json={
                "name": "Router 2",
                "router_ip": "192.168.1.2",
                "default_sampling": 200,
            },
        )

        response = client.get("/routers/")
        assert response.status_code == 200

        data = response.json()

        assert data["success"] is True
        assert isinstance(data["result"], list)
        assert len(data["result"]) >= 1


def test_get_router_by_id(test_db: Client):
    with TestClient(app) as client:
        create_response = client.post(
            "/routers/",
            json={
                "name": "Router 3",
                "router_ip": "192.168.1.3",
                "default_sampling": 300,
            },
        )
        router_id = create_response.json()["result"]["id"]

        response = client.get(f"/routers/{router_id}")
        assert response.status_code == 200

        data = response.json()

        assert data["success"] is True
        assert data["result"]["id"] == router_id
        assert data["result"]["name"] == "Router 3"


def test_get_router_not_found(test_db: Client):
    with TestClient(app) as client:
        response = client.get("/routers/nonexistent-id")

        assert response.status_code == 404


def test_update_router(test_db: Client):
    with TestClient(app) as client:
        create_response = client.post(
            "/routers/",
            json={
                "name": "Router 4",
                "router_ip": "192.168.1.4",
                "default_sampling": 400,
            },
        )
        router_id = create_response.json()["result"]["id"]

        response = client.put(
            f"/routers/{router_id}",
            json={
                "name": "Router 4 Updated",
                "router_ip": "192.168.1.40",
                "default_sampling": 500,
            },
        )
        assert response.status_code == 200

        data = response.json()

        assert data["success"] is True
        assert data["result"]["name"] == "Router 4 Updated"
        assert data["result"]["router_ip"] == "192.168.1.40"
        assert data["result"]["default_sampling"] == 500


def test_delete_router(test_db: Client):
    with TestClient(app) as client:
        create_response = client.post(
            "/routers/",
            json={
                "name": "Router 5",
                "router_ip": "192.168.1.5",
                "default_sampling": 500,
            },
        )
        router_id = create_response.json()["result"]["id"]

        response = client.delete(f"/routers/{router_id}")
        assert response.status_code == 204

        get_response = client.get(f"/routers/{router_id}")
        assert get_response.status_code == 404


def test_create_router_duplicate_ip(test_db: Client):
    with TestClient(app) as client:
        client.post(
            "/routers/",
            json={
                "name": "Router A",
                "router_ip": "10.0.0.1",
                "default_sampling": 100,
            },
        )

        response = client.post(
            "/routers/",
            json={
                "name": "Router B",
                "router_ip": "10.0.0.1",
                "default_sampling": 200,
            },
        )
        assert response.status_code == 409
