from __future__ import annotations

import base64
from io import BytesIO

from PIL import Image
from fastapi.testclient import TestClient

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
)
from app.repository import QuestionRepository
from app.seed_regression import SEEDS, seed_regression_questions
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


def test_identical_image_hits_library(tmp_path) -> None:
    image = make_image()
    processor = ImageProcessor(max_image_bytes=1024 * 1024)
    repository = QuestionRepository(tmp_path / "questions.db")
    repository.initialize()
    stored = AskResponse(
        request_id="seed",
        source="library",
        similar_questions=[],
        **solution().model_dump(),
    )
    repository.upsert("q_1001", "欧姆定律", processor.fingerprint(image), stored)
    fake_ai = FakeAiClient()
    service = AskService(repository, processor, fake_ai, match_threshold=0.92)
    request = AskRequest(
        image_base64=make_data_uri(image),
        crop_box=CropBox(x=0, y=0, w=120, h=80),
        rotation_degrees=0,
        subject="circuit",
    )

    import asyncio

    response = asyncio.run(service.ask(request))
    assert response.source == "library"
    assert response.final_answer == "I = 0.4A"
    assert response.similar_questions[0].question_id == "q_1001"
    assert not fake_ai.called


def test_missing_library_uses_ai(tmp_path) -> None:
    processor = ImageProcessor(max_image_bytes=1024 * 1024)
    repository = QuestionRepository(tmp_path / "questions.db")
    repository.initialize()
    fake_ai = FakeAiClient()
    service = AskService(repository, processor, fake_ai, match_threshold=0.92)
    image = make_image("black")
    request = AskRequest(
        image_base64=make_data_uri(image),
        crop_box=CropBox(x=0, y=0, w=120, h=80),
        rotation_degrees=0,
        subject="circuit",
    )

    import asyncio

    response = asyncio.run(service.ask(request))
    assert response.source == "ai"
    assert fake_ai.called


def test_pending_question_is_not_returned_to_user(tmp_path) -> None:
    image = make_image("green")
    processor = ImageProcessor(max_image_bytes=1024 * 1024)
    repository = QuestionRepository(tmp_path / "questions.db")
    repository.initialize()
    stored = AskResponse(
        request_id="seed",
        source="library",
        similar_questions=[],
        **solution().model_dump(),
    )
    repository.upsert(
        "q_pending",
        "只有标准答案、过程待审核",
        processor.fingerprint(image),
        stored,
        review_status="pending_solution",
        is_publishable=False,
        source_reference="教材答案页",
        question_image_path="question.jpg",
        answer_image_path="answer.jpg",
    )
    record = repository.get("q_pending")
    assert record is not None
    assert record.review_status == "pending_solution"
    assert not record.is_publishable

    fake_ai = FakeAiClient()
    service = AskService(repository, processor, fake_ai, match_threshold=0.92)
    request = AskRequest(
        image_base64=make_data_uri(image),
        crop_box=CropBox(x=0, y=0, w=120, h=80),
        rotation_degrees=0,
        subject="circuit",
    )

    import asyncio

    response = asyncio.run(service.ask(request))
    assert response.source == "ai"
    assert response.similar_questions == []
    assert fake_ai.called


def test_pending_question_cannot_be_published(tmp_path) -> None:
    import pytest

    processor = ImageProcessor(max_image_bytes=1024 * 1024)
    repository = QuestionRepository(tmp_path / "questions.db")
    repository.initialize()
    stored = AskResponse(
        request_id="seed",
        source="library",
        similar_questions=[],
        **solution().model_dump(),
    )

    with pytest.raises(ValueError, match="只有审核通过的题目才能发布"):
        repository.upsert(
            "q_invalid",
            "错误发布状态",
            processor.fingerprint(make_image()),
            stored,
            review_status="pending_solution",
            is_publishable=True,
        )


def test_real_regression_seeds_remain_unpublished(tmp_path) -> None:
    repository = QuestionRepository(tmp_path / "regression.db")
    assert seed_regression_questions(repository) == 3
    for seed in SEEDS:
        record = repository.get(seed.question_id)
        assert record is not None
        assert record.review_status == "pending_solution"
        assert not record.is_publishable


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
        library_match_threshold=0.92,
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
        library_match_threshold=0.92,
        max_image_bytes=1024 * 1024,
    )
    app = create_app(settings=settings, ai_client=FakeAiClient())

    with TestClient(app) as client:
        response = client.get("/api/v1/health")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "version": "0.3.0",
        "ai_provider": "deepseek",
        "ai_model": "deepseek-flash",
        "ai_configured": True,
        "library_questions": 0,
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
        library_match_threshold=0.92,
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
        library_match_threshold=0.92,
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
