from clickhouse_driver import Client
from fastapi.testclient import TestClient

from nm.main import app


def test_create_rule_threshold(test_db: Client):
    with TestClient(app) as client:
        response = client.post(
            "/rules/",
            json={
                "name": "Threshold Rule 1",
                "prefixes": ["10.0.0.0/8"],
                "type": "threshold",
                "bandwidth_threshold": 1000,
                "packet_threshold": 500,
                "duration": 60,
            },
        )
        assert response.status_code == 201

        data = response.json()

        assert data["success"] is True
        assert data["result"]["name"] == "Threshold Rule 1"
        assert data["result"]["prefixes"] == ["10.0.0.0/8"]
        assert data["result"]["type"] == "threshold"
        assert data["result"]["bandwidth_threshold"] == 1000
        assert data["result"]["packet_threshold"] == 500
        assert data["result"]["duration"] == 60
        assert "id" in data["result"]


def test_create_rule_zscore(test_db: Client):
    with TestClient(app) as client:
        response = client.post(
            "/rules/",
            json={
                "name": "Zscore Rule 1",
                "prefixes": ["192.168.0.0/16"],
                "type": "zscore",
                "zscore_sensitivity": "high",
                "zscore_target": "bits",
            },
        )
        assert response.status_code == 201

        data = response.json()

        assert data["success"] is True
        assert data["result"]["name"] == "Zscore Rule 1"
        assert data["result"]["type"] == "zscore"
        assert data["result"]["zscore_sensitivity"] == "high"
        assert data["result"]["zscore_target"] == "bits"


def test_create_rule_multiple_prefixes(test_db: Client):
    with TestClient(app) as client:
        response = client.post(
            "/rules/",
            json={
                "name": "Multi Prefix Rule",
                "prefixes": ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"],
                "type": "threshold",
                "bandwidth_threshold": 500,
            },
        )
        assert response.status_code == 201

        data = response.json()

        assert data["success"] is True
        assert len(data["result"]["prefixes"]) == 3


def test_get_rules(test_db: Client):
    with TestClient(app) as client:
        client.post(
            "/rules/",
            json={
                "name": "List Test Rule",
                "prefixes": ["10.1.0.0/16"],
                "type": "threshold",
                "bandwidth_threshold": 100,
            },
        )

        response = client.get("/rules/")
        assert response.status_code == 200

        data = response.json()

        assert data["success"] is True
        assert isinstance(data["result"], list)
        assert len(data["result"]) >= 1


def test_get_rule_by_id(test_db: Client):
    with TestClient(app) as client:
        create_response = client.post(
            "/rules/",
            json={
                "name": "Get By ID Rule",
                "prefixes": ["10.2.0.0/16"],
                "type": "threshold",
                "bandwidth_threshold": 200,
            },
        )
        rule_id = create_response.json()["result"]["id"]

        response = client.get(f"/rules/{rule_id}")
        assert response.status_code == 200

        data = response.json()

        assert data["success"] is True
        assert data["result"]["id"] == rule_id
        assert data["result"]["name"] == "Get By ID Rule"


def test_get_rule_not_found(test_db: Client):
    with TestClient(app) as client:
        response = client.get("/rules/nonexistent-id")

        assert response.status_code == 404


def test_update_rule(test_db: Client):
    with TestClient(app) as client:
        create_response = client.post(
            "/rules/",
            json={
                "name": "Update Test Rule",
                "prefixes": ["10.3.0.0/16"],
                "type": "threshold",
                "bandwidth_threshold": 300,
            },
        )
        rule_id = create_response.json()["result"]["id"]

        response = client.put(
            f"/rules/{rule_id}",
            json={
                "name": "Updated Rule",
                "prefixes": ["10.3.0.0/16", "10.4.0.0/16"],
                "type": "zscore",
                "zscore_sensitivity": "medium",
                "zscore_target": "packets",
            },
        )
        assert response.status_code == 200

        data = response.json()

        assert data["success"] is True
        assert data["result"]["name"] == "Updated Rule"
        assert data["result"]["type"] == "zscore"
        assert data["result"]["zscore_sensitivity"] == "medium"
        assert len(data["result"]["prefixes"]) == 2


def test_delete_rule(test_db: Client):
    with TestClient(app) as client:
        create_response = client.post(
            "/rules/",
            json={
                "name": "Delete Test Rule",
                "prefixes": ["10.5.0.0/16"],
                "type": "threshold",
                "bandwidth_threshold": 400,
            },
        )
        rule_id = create_response.json()["result"]["id"]

        response = client.delete(f"/rules/{rule_id}")
        assert response.status_code == 204

        get_response = client.get(f"/rules/{rule_id}")
        assert get_response.status_code == 404


def test_create_rule_empty_prefixes(test_db: Client):
    with TestClient(app) as client:
        response = client.post(
            "/rules/",
            json={
                "name": "Invalid Rule",
                "prefixes": [],
                "type": "threshold",
                "bandwidth_threshold": 100,
            },
        )
        assert response.status_code == 422


def test_create_rule_invalid_type(test_db: Client):
    with TestClient(app) as client:
        response = client.post(
            "/rules/",
            json={
                "name": "Invalid Type Rule",
                "prefixes": ["10.0.0.0/8"],
                "type": "invalid_type",
                "bandwidth_threshold": 100,
            },
        )
        assert response.status_code == 422
