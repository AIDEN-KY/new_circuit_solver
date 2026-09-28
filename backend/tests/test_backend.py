from __future__ import annotations

import base64
from io import BytesIO

from PIL import Image
from fastapi.testclient import TestClient

from app.account_repository import AccountRepository, DuplicateGrantError
from app.config import Settings
from app.image_processing import ImageProcessor
from app.main import create_app
from app.models import (
    AiSolution,
    AskRequest,
    AskResponse,
    ChatResponse,
    CropBox,
    SolutionStep,
    UnitCheck,
    SpiceNetlist,
)
from app.service import AskService


def make_image(color: str = "white") -> bytes:
    image = Image.new("RGB", (120, 80), color=color)
    output = BytesIO()
    image.save(output, format="PNG")
    return output.getvalue()


def make_data_uri(image: bytes) -> str:
    return "data:image/png;base64," + base64.b64encode(image).decode("ascii")


def solution() -> AiSolution:
    return AiSolution(
        confidence="high",
        final_answer="I = 0.4A",
        final_answer_latex=r"I = 0.4\\text{A}",
        steps=[
            SolutionStep(
                step_number=1,
                title="计算电流",
                content="根据欧姆定律计算。",
                latex=r"I=\\frac{U}{R}",
            )
        ],
        knowledge_points=["欧姆定律"],
        unit_check=UnitCheck(
            expected_unit="A", actual_unit="A", passed=True, note=""
        ),
        uncertain=[],
    )


class FakeAiClient:
    def __init__(self) -> None:
        self.called = False

    async def solve(self, image_bytes: bytes) -> AiSolution:
        self.called = True
        return solution()

    async def follow_up(
        self, image_bytes: bytes, original_response, messages, message: str
    ) -> ChatResponse:
        self.called = True
        return ChatResponse(answer=f"已根据补充条件核对：${message}$")


class ModifyAiClient(FakeAiClient):
    async def follow_up(
        self, image_bytes: bytes | None, original_response, messages, message: str
    ) -> ChatResponse:
        self.called = True
        return ChatResponse(
            answer="已更新参数并重新计算。",
            intent="modify_circuit",
            updated_netlist=SpiceNetlist(
                raw="V1 in 0 DC 12\nR1 in 0 12\n.op\n.end"
            ),
        )

    async def solve_from_netlist(self, netlist: str, question: str) -> AiSolution:
        return solution()


def test_every_image_goes_directly_to_ai() -> None:
    import asyncio

    fake_ai = FakeAiClient()
    service = AskService(ImageProcessor(max_image_bytes=1024 * 1024), fake_ai)
    request = AskRequest(
        image_base64=make_data_uri(make_image("green")),
        crop_box=CropBox(x=0, y=0, w=120, h=80),
        rotation_degrees=0,
        subject="circuit",
    )
    response = asyncio.run(service.ask(request))
    assert fake_ai.called
    assert response.source == "ai"
    assert response.similar_questions == []


def test_http_api_returns_flutter_contract(tmp_path) -> None:
    fake_ai = FakeAiClient()
    settings = Settings(
        database_path=tmp_path / "api.db",
        ai_provider="ollama",
        ai_model="unused-in-test",
        ai_timeout_seconds=5,
        ai_max_output_tokens=1024,
        ollama_base_url="http://127.0.0.1:11434",
        ai_api_base_url="",
        ai_api_key="",
        max_image_bytes=1024 * 1024,
    )
    app = create_app(settings=settings, ai_client=fake_ai)
    image = make_image("blue")
    payload = {
        "image_base64": make_data_uri(image),
        "crop_box": {"x": 0, "y": 0, "w": 120, "h": 80},
        "rotation_degrees": 0,
        "subject": "circuit",
    }

    with TestClient(app) as client:
        response = client.post("/api/v1/ask", json=payload)

    assert response.status_code == 200
    body = response.json()
    assert body["source"] == "ai"
    assert body["final_answer"] == "I = 0.4A"
    assert body["steps"][0]["step_number"] == 1
    assert body["unit_check"]["passed"] is True


def test_health_endpoint_reports_safe_service_status(tmp_path) -> None:
    settings = Settings(
        database_path=tmp_path / "health.db",
        ai_provider="deepseek",
        ai_model="deepseek-flash",
        ai_timeout_seconds=5,
        ai_max_output_tokens=1024,
        ollama_base_url="http://127.0.0.1:11434",
        ai_api_base_url="https://api.example.test",
        ai_api_key="secret-for-test",
        max_image_bytes=1024 * 1024,
    )
    app = create_app(settings=settings, ai_client=FakeAiClient())

    with TestClient(app) as client:
        response = client.get("/api/v1/health")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "version": "0.7.0",
        "ai_provider": "deepseek",
        "ai_model": "deepseek-flash",
        "ai_configured": True,
        "library_questions": 0,
        "auth_required": False,
    }
    assert "secret-for-test" not in response.text


def test_http_api_rejects_invalid_crop(tmp_path) -> None:
    settings = Settings(
        database_path=tmp_path / "invalid.db",
        ai_provider="ollama",
        ai_model="unused-in-test",
        ai_timeout_seconds=5,
        ai_max_output_tokens=1024,
        ollama_base_url="http://127.0.0.1:11434",
        ai_api_base_url="",
        ai_api_key="",
        max_image_bytes=1024 * 1024,
    )
    app = create_app(settings=settings, ai_client=FakeAiClient())
    payload = {
        "image_base64": make_data_uri(make_image()),
        "crop_box": {"x": 1000, "y": 1000, "w": 10, "h": 10},
        "rotation_degrees": 0,
        "subject": "circuit",
    }

    with TestClient(app) as client:
        response = client.post("/api/v1/ask", json=payload)

    assert response.status_code == 400
    assert response.json()["detail"] == "框选区域超出图片范围"


def test_rotation_happens_before_crop() -> None:
    processor = ImageProcessor(max_image_bytes=1024 * 1024)
    source = Image.new("RGB", (120, 80), color="white")
    output = BytesIO()
    source.save(output, format="PNG")
    request = AskRequest(
        image_base64=make_data_uri(output.getvalue()),
        crop_box=CropBox(x=0, y=0, w=80, h=120),
        rotation_degrees=90,
        subject="circuit",
    )

    prepared = Image.open(BytesIO(processor.prepare(request)))

    assert prepared.size == (80, 120)


def test_chat_endpoint_keeps_flutter_contract(tmp_path) -> None:
    fake_ai = FakeAiClient()
    settings = Settings(
        database_path=tmp_path / "chat.db",
        ai_provider="ollama",
        ai_model="unused-in-test",
        ai_timeout_seconds=5,
        ai_max_output_tokens=1024,
        ollama_base_url="http://127.0.0.1:11434",
        ai_api_base_url="",
        ai_api_key="",
        max_image_bytes=1024 * 1024,
    )
    app = create_app(settings=settings, ai_client=fake_ai)
    original = AskResponse(
        request_id="req_chat",
        source="ai",
        similar_questions=[],
        **solution().model_dump(),
    )
    payload = {
        "image_base64": make_data_uri(make_image()),
        "crop_box": {"x": 0, "y": 0, "w": 120, "h": 80},
        "rotation_degrees": 0,
        "subject": "circuit",
        "original_response": original.model_dump(),
        "messages": [],
        "message": "R2 是 20Ω",
    }

    with TestClient(app) as client:
        response = client.post("/api/v1/chat", json=payload)

    assert response.status_code == 200
    assert "R2 是 20Ω" in response.json()["answer"]
    assert fake_ai.called


def test_chat_modification_validates_and_recalculates_netlist(tmp_path) -> None:
    fake_ai = ModifyAiClient()
    settings = Settings(
        database_path=tmp_path / "chat-modify.db",
        ai_provider="ollama",
        ai_model="unused-in-test",
        ai_timeout_seconds=5,
        ai_max_output_tokens=1024,
        ollama_base_url="http://127.0.0.1:11434",
        ai_api_base_url="",
        ai_api_key="",
        max_image_bytes=1024 * 1024,
    )
    app = create_app(settings=settings, ai_client=fake_ai)
    original = AskResponse(
        request_id="req_modify",
        source="ai",
        similar_questions=[],
        **solution().model_dump(),
    )
    payload = {
        "image_base64": make_data_uri(make_image()),
        "crop_box": {"x": 0, "y": 0, "w": 120, "h": 80},
        "rotation_degrees": 0,
        "subject": "circuit",
        "original_response": original.model_dump(),
        "messages": [],
        "message": "把R1改成12Ω并重新计算",
    }
    with TestClient(app) as client:
        response = client.post("/api/v1/chat", json=payload)
    assert response.status_code == 200
    body = response.json()
    assert body["intent"] == "modify_circuit"
    assert body["updated_netlist"]["validation_passed"] is True
    assert body["recalculated_response"]["source"] == "ai"


def test_account_auth_and_server_side_free_usage(tmp_path) -> None:
    settings = Settings(
        database_path=tmp_path / "accounts.db",
        ai_provider="ollama",
        ai_model="unused-in-test",
        ai_timeout_seconds=5,
        ai_max_output_tokens=1024,
        ollama_base_url="http://127.0.0.1:11434",
        ai_api_base_url="",
        ai_api_key="",
        max_image_bytes=1024 * 1024,
        auth_required=True,
        initial_free_uses=3,
        solve_price_fen=10,
    )
    app = create_app(settings=settings, ai_client=FakeAiClient())
    payload = {
        "image_base64": make_data_uri(make_image("purple")),
        "crop_box": {"x": 0, "y": 0, "w": 120, "h": 80},
        "rotation_degrees": 0,
        "subject": "circuit",
    }

    with TestClient(app) as client:
        assert client.post("/api/v1/ask", json=payload).status_code == 401
        assert client.get("/api/v1/account/activities").status_code == 401
        register = client.post(
            "/api/v1/auth/register",
            json={"username": "student_01", "password": "password123"},
        )
        assert register.status_code == 201
        token = register.json()["access_token"]
        assert register.json()["account"]["free_uses_remaining"] == 3
        headers = {"Authorization": f"Bearer {token}"}
        initial_activities = client.get(
            "/api/v1/account/activities", headers=headers
        ).json()
        assert initial_activities[0]["event_type"] == "register_bonus"
        assert initial_activities[0]["free_uses_delta"] == 3

        for expected in (2, 1, 0):
            assert client.post("/api/v1/ask", json=payload, headers=headers).status_code == 200
            profile = client.get("/api/v1/account/me", headers=headers)
            assert profile.json()["free_uses_remaining"] == expected

        exhausted = client.post("/api/v1/ask", json=payload, headers=headers)
        assert exhausted.status_code == 402
        assert "剩余搜题次数不足" in exhausted.json()["detail"]
        activities = client.get(
            "/api/v1/account/activities", headers=headers
        ).json()
        deductions = [
            item
            for item in activities
            if item["event_type"] == "solve_reserved"
        ]
        assert len(deductions) == 3
        assert all(item["free_uses_delta"] == -1 for item in deductions)


def test_failed_solve_refunds_reserved_free_usage(tmp_path) -> None:
    class BrokenAiClient(FakeAiClient):
        async def solve(self, image_bytes: bytes) -> AiSolution:
            from app.providers import AiProviderError

            raise AiProviderError("模型暂不可用")

    settings = Settings(
        database_path=tmp_path / "refund.db",
        ai_provider="ollama",
        ai_model="unused-in-test",
        ai_timeout_seconds=5,
        ai_max_output_tokens=1024,
        ollama_base_url="http://127.0.0.1:11434",
        ai_api_base_url="",
        ai_api_key="",
        max_image_bytes=1024 * 1024,
        auth_required=True,
    )
    app = create_app(settings=settings, ai_client=BrokenAiClient())
    payload = {
        "image_base64": make_data_uri(make_image("orange")),
        "crop_box": {"x": 0, "y": 0, "w": 120, "h": 80},
        "rotation_degrees": 0,
        "subject": "circuit",
    }

    with TestClient(app) as client:
        register = client.post(
            "/api/v1/auth/register",
            json={"username": "refund_user", "password": "password123"},
        )
        headers = {"Authorization": f"Bearer {register.json()['access_token']}"}
        failed = client.post("/api/v1/ask", json=payload, headers=headers)
        profile = client.get("/api/v1/account/me", headers=headers)
        activities = client.get(
            "/api/v1/account/activities", headers=headers
        ).json()

    assert failed.status_code == 503
    assert profile.json()["free_uses_remaining"] == 3
    assert activities[0]["event_type"] == "solve_refunded"
    assert activities[0]["free_uses_delta"] == 1


def test_manual_grant_adds_uses_once_and_records_audit(tmp_path) -> None:
    import pytest

    repository = AccountRepository(
        tmp_path / "manual-grant.db",
        initial_free_uses=3,
        solve_price_fen=10,
        session_days=30,
    )
    repository.initialize()
    session = repository.register("manual_user", "password123")

    account = repository.grant_uses(
        session.account.id,
        10,
        operator="admin_01",
        reference_id="transfer_20260927_001",
        note="内测人工发放",
    )

    assert account.free_uses_remaining == 13
    assert repository.list_ledger(account.id)[0].event_type == "adjustment"
    assert repository.list_ledger(account.id)[0].free_uses_delta == 10
    with pytest.raises(DuplicateGrantError, match="禁止重复发放"):
        repository.grant_uses(
            session.account.id,
            10,
            operator="admin_01",
            reference_id="transfer_20260927_001",
        )
    assert repository.authenticate(session.token).free_uses_remaining == 13
