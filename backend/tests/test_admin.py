from pathlib import Path

from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app


def test_admin_can_search_and_grant_once(tmp_path: Path) -> None:
    settings = Settings(
        database_path=tmp_path / "admin.db",
        ai_provider="ollama",
        ai_model="unused",
        ai_timeout_seconds=5,
        ai_max_output_tokens=128,
        ollama_base_url="http://127.0.0.1:11434",
        ai_api_base_url="",
        ai_api_key="",
        max_image_bytes=1024 * 1024,
        auth_required=True,
        initial_free_uses=3,
        solve_price_fen=10,
        admin_username="admin",
        admin_password="admin-password-for-test",
    )
    app = create_app(settings=settings)
    with TestClient(app) as client:
        registered = client.post(
            "/api/v1/auth/register",
            json={"username": "admin_test_user", "password": "password123"},
        )
        user_id = registered.json()["account"]["id"]
        login = client.post(
            "/api/v1/admin/login",
            json={"username": "admin", "password": "admin-password-for-test"},
        )
        assert login.status_code == 200
        headers = {"Authorization": f"Bearer {login.json()['access_token']}"}
        assert client.get("/api/v1/admin/users?keyword=admin_test_user", headers=headers).json()[0]["id"] == user_id
        grant = client.post(
            f"/api/v1/admin/users/{user_id}/grant-uses",
            headers=headers,
            json={"uses": 10, "reference_id": "test-ref-001", "note": "测试授权"},
        )
        assert grant.status_code == 200
        assert grant.json()["free_uses_remaining"] == 13
        duplicate = client.post(
            f"/api/v1/admin/users/{user_id}/grant-uses",
            headers=headers,
            json={"uses": 10, "reference_id": "test-ref-001", "note": "重复测试"},
        )
        assert duplicate.status_code == 409
