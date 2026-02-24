from clickhouse_driver import Client
from fastapi.testclient import TestClient

from nm.main import app


def test_create_expression(test_db: Client):
    with TestClient(app) as client:
        response = client.post(
            "/expressions/",
            json={
                "name": "HTTPS Traffic",
                "expression": "proto == 6 && dst_port == 443",
            },
        )
        assert response.status_code == 201

        data = response.json()

        assert data["success"] is True
        assert data["result"]["name"] == "HTTPS Traffic"
        assert data["result"]["expression"] == "proto == 6 && dst_port == 443"
        assert "id" in data["result"]


def test_get_expressions(test_db: Client):
    with TestClient(app) as client:
        client.post(
            "/expressions/",
            json={
                "name": "List Test Expression",
                "expression": "proto == 17",
            },
        )

        response = client.get("/expressions/")
        assert response.status_code == 200

        data = response.json()

        assert data["success"] is True
        assert isinstance(data["result"], list)
        assert len(data["result"]) >= 1


def test_get_expression_by_id(test_db: Client):
    with TestClient(app) as client:
        create_response = client.post(
            "/expressions/",
            json={
                "name": "Get By ID Expression",
                "expression": "dst_port == 80",
            },
        )
        expression_id = create_response.json()["result"]["id"]

        response = client.get(f"/expressions/{expression_id}")
        assert response.status_code == 200

        data = response.json()

        assert data["success"] is True
        assert data["result"]["id"] == expression_id
        assert data["result"]["name"] == "Get By ID Expression"


def test_get_expression_not_found(test_db: Client):
    with TestClient(app) as client:
        response = client.get("/expressions/nonexistent-id")

        assert response.status_code == 404


def test_update_expression(test_db: Client):
    with TestClient(app) as client:
        create_response = client.post(
            "/expressions/",
            json={
                "name": "Update Test Expression",
                "expression": "proto == 6",
            },
        )
        expression_id = create_response.json()["result"]["id"]

        response = client.put(
            f"/expressions/{expression_id}",
            json={
                "name": "Updated Expression",
                "expression": "proto == 6 && dst_port == 8080",
            },
        )
        assert response.status_code == 200

        data = response.json()

        assert data["success"] is True
        assert data["result"]["name"] == "Updated Expression"
        assert data["result"]["expression"] == "proto == 6 && dst_port == 8080"


def test_delete_expression(test_db: Client):
    with TestClient(app) as client:
        create_response = client.post(
            "/expressions/",
            json={
                "name": "Delete Test Expression",
                "expression": "proto == 1",
            },
        )
        expression_id = create_response.json()["result"]["id"]

        response = client.delete(f"/expressions/{expression_id}")
        assert response.status_code == 204

        get_response = client.get(f"/expressions/{expression_id}")
        assert get_response.status_code == 404
