from __future__ import annotations

import base64
import asyncio
from dataclasses import replace
from io import BytesIO

from fastapi.testclient import TestClient
from PIL import Image

from app.backup_database import backup_database, verify_database
from app.config import Settings
from app.main import create_app
from app.models import AiSolution, ChatResponse, SolutionStep, UnitCheck
from app.rate_limit import AccountBusyError, RateLimitExceeded, SlidingWindowLimiter, SolveConcurrencyGuard


class CountingAi:
    def __init__(self, *, fail: bool = False) -> None:
        self.calls = 0
        self.fail = fail

    async def solve(self, image_bytes: bytes) -> AiSolution:
        self.calls += 1
        if self.fail:
            raise RuntimeError("test failure")
        return AiSolution(
            confidence="high", final_answer="I=1A",
            final_answer_latex=r"I=1\,\mathrm{A}",
            steps=[SolutionStep(step_number=1, title="求解", content="$I=1A$", latex="I=1A")],
            knowledge_points=["欧姆定律"],
            unit_check=UnitCheck(expected_unit="A", actual_unit="A", passed=True, note=""),
            uncertain=[],
        )

    async def follow_up(self, image_bytes, original_response, messages, message):
        return ChatResponse(answer="已核对")


def settings(tmp_path, **changes) -> Settings:
    value = Settings(
        database_path=tmp_path / "release170.db", ai_provider="ollama",
        ai_model="test", ai_timeout_seconds=5, ai_max_output_tokens=128,
        ollama_base_url="http://127.0.0.1:11434", ai_api_base_url="",
        ai_api_key="",
        max_image_bytes=1024 * 1024, auth_required=True,
        initial_free_uses=3, admin_username="admin",
        admin_password="admin-password-for-test",
    )
    return replace(value, **changes)


def payload(client_request_id: str = "request-0001") -> dict:
    image = Image.new("RGB", (40, 30), "white")
    output = BytesIO(); image.save(output, format="PNG")
    return {
        "image_base64": "data:image/png;base64," + base64.b64encode(output.getvalue()).decode(),
        "crop_box": {"x": 0, "y": 0, "w": 40, "h": 30},
        "rotation_degrees": 0, "subject": "circuit",
        "client_request_id": client_request_id,
    }


def register(client: TestClient, username: str = "tester170") -> tuple[str, dict]:
    response = client.post("/api/v1/auth/register", json={"username": username, "password": "password123"})
    assert response.status_code == 201
    return response.json()["access_token"], response.json()["account"]


def admin_headers(client: TestClient) -> dict:
    response = client.post("/api/v1/admin/login", json={"username": "admin", "password": "admin-password-for-test"})
    return {"Authorization": "Bearer " + response.json()["access_token"]}


def test_public_process_has_no_admin_routes(tmp_path) -> None:
    app = create_app(settings(tmp_path, admin_routes_enabled=False), ai_client=CountingAi())
    with TestClient(app) as client:
        assert client.get("/admin").status_code == 404
        assert client.post("/api/v1/admin/login", json={"username": "admin", "password": "admin-password-for-test"}).status_code == 404


def test_dynamic_bonus_maintenance_version_disable_and_adjustment(tmp_path) -> None:
    app = create_app(settings(tmp_path), ai_client=CountingAi())
    with TestClient(app) as client:
        admin = admin_headers(client)
        current = client.get("/api/v1/admin/config", headers=admin).json()
        update = {key: value for key, value in current.items() if key not in {"revision", "updated_at"}}
        update["initial_free_uses"] = 5
        update["min_supported_version"] = "1.7.0"
        assert client.put("/api/v1/admin/config", headers=admin, json=update).status_code == 200
        token, account = register(client)
        assert account["free_uses_remaining"] == 5
        user_id = account["id"]
        adjusted = client.post(f"/api/v1/admin/users/{user_id}/adjust-uses", headers=admin, json={"delta": -2, "reference_id": "adjust-001", "note": "测试扣减"})
        assert adjusted.json()["free_uses_remaining"] == 3
        headers = {"Authorization": f"Bearer {token}", "X-App-Version": "1.6.9"}
        assert client.post("/api/v1/ask", headers=headers, json=payload()).status_code == 426
        update["maintenance_mode"] = True
        assert client.put("/api/v1/admin/config", headers=admin, json=update).status_code == 200
        headers["X-App-Version"] = "1.7.0"
        assert client.post("/api/v1/ask", headers=headers, json=payload()).status_code == 503
        assert client.get("/api/v1/account/me", headers=headers).status_code == 200
        assert client.post(f"/api/v1/admin/users/{user_id}/status", headers=admin, json={"status": "disabled", "note": "测试停用"}).status_code == 200
        assert client.get("/api/v1/account/me", headers=headers).status_code == 401


def test_idempotent_request_reuses_result_and_charge(tmp_path) -> None:
    ai = CountingAi(); app = create_app(settings(tmp_path), ai_client=ai)
    with TestClient(app) as client:
        token, _ = register(client, "idempotent_user")
        headers = {"Authorization": f"Bearer {token}", "X-App-Version": "1.7.0"}
        first = client.post("/api/v1/ask", headers=headers, json=payload("stable-request-01"))
        second = client.post("/api/v1/ask", headers=headers, json=payload("stable-request-01"))
        assert first.status_code == second.status_code == 200
        assert first.json()["request_id"] == second.json()["request_id"]
        assert ai.calls == 1
        assert client.get("/api/v1/account/me", headers=headers).json()["free_uses_remaining"] == 2


def test_request_size_and_backup_restore_check(tmp_path) -> None:
    app = create_app(settings(tmp_path, max_request_bytes=256), ai_client=CountingAi())
    with TestClient(app) as client:
        assert client.post("/api/v1/auth/register", content=b"x" * 300, headers={"content-type": "application/json"}).status_code == 413
    backup = backup_database(tmp_path / "release170.db", tmp_path / "backups", keep=14)
    assert backup.is_file() and verify_database(backup)


def test_rate_limit_and_one_request_per_account() -> None:
    async def scenario() -> None:
        limiter = SlidingWindowLimiter()
        await limiter.check("register:ip", limit=2, window_seconds=60)
        await limiter.check("register:ip", limit=2, window_seconds=60)
        try:
            await limiter.check("register:ip", limit=2, window_seconds=60)
            raise AssertionError("第三次请求应被限流")
        except RateLimitExceeded:
            pass

        guard = SolveConcurrencyGuard(2)
        entered = asyncio.Event()
        release = asyncio.Event()

        async def hold() -> None:
            async with guard.acquire("same-user"):
                entered.set()
                await release.wait()

        task = asyncio.create_task(hold())
        await entered.wait()
        try:
            async with guard.acquire("same-user"):
                raise AssertionError("同账号不应并行进入")
        except AccountBusyError:
            pass
        release.set()
        await task

    asyncio.run(scenario())
