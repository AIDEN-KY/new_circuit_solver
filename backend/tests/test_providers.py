from __future__ import annotations

import asyncio
import json
from pathlib import Path

import httpx
import pytest

from app.ai_solver import EXTRACTION_SYSTEM_PROMPT, SOLUTION_SYSTEM_PROMPT, AiSolver
from app.config import Settings
from app.models import AiSolution, CircuitExtraction, SolutionStep, UnitCheck
from app.providers.base import AiProviderResult
from app.providers.deepseek import DeepSeekVisionProvider
from app.providers.errors import (
    AiProviderConfigurationError,
    AiProviderResponseError,
    AiProviderTimeoutError,
)
from app.providers.factory import create_ai_provider
from app.providers.ollama import OllamaProvider
from app.providers.openai_compatible import OpenAiCompatibleVisionProvider


def valid_solution_payload() -> dict[str, object]:
    return AiSolution(
        confidence="medium",
        final_answer="U = 12V",
        final_answer_latex=r"U=12\\text{V}",
        steps=[
            SolutionStep(
                step_number=1,
                title="列方程",
                content="根据基尔霍夫电压定律列方程。",
                latex=r"\\sum U=0",
            )
        ],
        knowledge_points=["基尔霍夫电压定律"],
        unit_check=UnitCheck(
            expected_unit="V", actual_unit="V", passed=True, note=""
        ),
        uncertain=[],
    ).model_dump()


def test_solver_prompts_preserve_source_deactivation_rules() -> None:
    assert "连续导线相连表示短路" in EXTRACTION_SYSTEM_PROMPT
    assert "独立理想电压源置零等效为短路" in SOLUTION_SYSTEM_PROMPT
    assert "独立理想电流源置零等效为开路" in SOLUTION_SYSTEM_PROMPT
    assert "保留源输出=原输出-被移除源贡献" in SOLUTION_SYSTEM_PROMPT


def test_target_matching_ignores_latex_subscript_formatting() -> None:
    assert AiSolver._contains_target(r"U_{ab}=7\,\mathrm{V}", "Uab")
    assert AiSolver._contains_target(r"U_{ab}=7\,\mathrm{V}", "U_ab")


def valid_extraction_payload() -> dict[str, object]:
    return CircuitExtraction(
        problem_text="已知电压，求U。",
        target_variables=["U"],
        components=[],
        connections=[],
        given_conditions=["电压为12V"],
        diagram_notes=[],
        uncertain=[],
    ).model_dump()


def make_settings(provider: str = "ollama") -> Settings:
    return Settings(
        database_path=Path("unused.db"),
        ai_provider=provider,
        ai_model="vision-model",
        ai_timeout_seconds=5,
        ai_max_output_tokens=1024,
        ollama_base_url="http://ollama.test",
        ai_api_base_url="https://vision.example/v1",
        ai_api_key="secret-from-environment",
        max_image_bytes=1024,
    )


def test_provider_factory_is_configuration_driven() -> None:
    assert isinstance(create_ai_provider(make_settings()), OllamaProvider)
    assert isinstance(
        create_ai_provider(make_settings("openai_compatible")),
        OpenAiCompatibleVisionProvider,
    )
    assert isinstance(
        create_ai_provider(make_settings("deepseek")),
        DeepSeekVisionProvider,
    )
    with pytest.raises(AiProviderConfigurationError):
        create_ai_provider(make_settings("unknown"))


def test_ollama_provider_sends_image_schema_and_parses_json() -> None:
    async def run() -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            body = json.loads(request.content)
            assert request.url.path == "/api/chat"
            assert body["model"] == "qwen3-vl:4b-instruct"
            assert body["messages"][1]["images"]
            assert body["format"]["type"] == "object"
            assert body["options"]["num_predict"] == 1024
            return httpx.Response(
                200,
                json={"message": {"content": json.dumps(valid_solution_payload())}},
            )

        provider = OllamaProvider(
            base_url="http://ollama.test",
            model="qwen3-vl:4b-instruct",
            timeout_seconds=5,
            transport=httpx.MockTransport(handler),
        )
        result = await provider.generate(request=provider_request())
        assert result.provider == "ollama"
        assert result.payload["final_answer"] == "U = 12V"

    asyncio.run(run())


def test_ollama_timeout_is_normalized() -> None:
    async def run() -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            raise httpx.ReadTimeout("too slow", request=request)

        provider = OllamaProvider(
            base_url="http://ollama.test",
            model="vision-model",
            timeout_seconds=0.01,
            transport=httpx.MockTransport(handler),
        )
        with pytest.raises(AiProviderTimeoutError):
            await provider.generate(provider_request())

    asyncio.run(run())


def test_cloud_provider_rejects_missing_credentials_before_network_call() -> None:
    provider = OpenAiCompatibleVisionProvider(
        base_url="",
        api_key="",
        model="vision-model",
        timeout_seconds=5,
    )
    with pytest.raises(AiProviderConfigurationError):
        asyncio.run(provider.generate(provider_request()))


def test_deepseek_provider_uses_responses_vision_and_schema() -> None:
    async def run() -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            body = json.loads(request.content)
            assert request.url.path == "/responses"
            assert request.headers["Authorization"] == "Bearer secret"
            assert body["model"] == "deepseek-flash"
            assert body["input"][0]["content"][1]["type"] == "input_image"
            assert body["input"][0]["content"][1]["image_url"].startswith(
                "data:image/jpeg;base64,"
            )
            assert body["text"]["format"]["type"] == "json_schema"
            assert body["max_output_tokens"] == 1024
            assert body["reasoning"]["effort"] == "none"
            return httpx.Response(
                200,
                json={
                    "output": [
                        {"type": "reasoning", "content": []},
                        {
                            "type": "message",
                            "content": [
                                {
                                    "type": "output_text",
                                    "text": json.dumps(valid_solution_payload()),
                                }
                            ],
                        },
                    ]
                },
            )

        provider = DeepSeekVisionProvider(
            base_url="https://api.deepseek.com",
            api_key="secret",
            model="deepseek-flash",
            timeout_seconds=5,
            transport=httpx.MockTransport(handler),
        )
        result = await provider.generate(provider_request())
        assert result.provider == "deepseek"
        assert result.payload["final_answer"] == "U = 12V"

    asyncio.run(run())


def test_deepseek_provider_rejects_missing_key() -> None:
    provider = DeepSeekVisionProvider(
        base_url="https://api.deepseek.com",
        api_key="",
        model="deepseek-flash",
        timeout_seconds=5,
    )
    with pytest.raises(AiProviderConfigurationError):
        asyncio.run(provider.generate(provider_request()))


def test_deepseek_provider_supports_text_only_reasoning_stage() -> None:
    async def run() -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            body = json.loads(request.content)
            assert body["input"][0]["content"] == [
                {"type": "input_text", "text": "structured circuit"}
            ]
            assert body["reasoning"]["effort"] == "low"
            assert body["max_output_tokens"] == 4096
            return httpx.Response(
                200,
                json={
                    "status": "completed",
                    "output": [
                        {
                            "type": "message",
                            "content": [
                                {
                                    "type": "output_text",
                                    "text": json.dumps(valid_solution_payload()),
                                }
                            ],
                        }
                    ],
                },
            )

        from app.providers.base import AiProviderRequest

        provider = DeepSeekVisionProvider(
            base_url="https://api.deepseek.com",
            api_key="secret",
            model="deepseek-flash",
            timeout_seconds=5,
            transport=httpx.MockTransport(handler),
        )
        result = await provider.generate(
            AiProviderRequest(
                image_bytes=None,
                system_prompt="system",
                user_prompt="structured circuit",
                json_schema=AiSolution.model_json_schema(),
                reasoning_effort="low",
                max_output_tokens=4096,
            )
        )
        assert result.payload["final_answer"] == "U = 12V"

    asyncio.run(run())


def test_solver_rejects_provider_payload_outside_contract() -> None:
    class InvalidProvider:
        name = "invalid"
        model = "invalid"

        async def generate(self, request):
            return AiProviderResult({}, self.name, self.model, 0.01)

    with pytest.raises(AiProviderResponseError):
        asyncio.run(AiSolver(InvalidProvider()).solve(b"image"))  # type: ignore[arg-type]


def test_solver_reuses_calculation_latex_when_final_latex_is_missing() -> None:
    class MissingFinalLatexProvider:
        name = "test"
        model = "test"

        async def generate(self, request):
            if request.structured_output_name == "circuit_extraction":
                return AiProviderResult(
                    valid_extraction_payload(), self.name, self.model, 0.01
                )
            payload = valid_solution_payload()
            payload["final_answer_latex"] = ""
            return AiProviderResult(payload, self.name, self.model, 0.01)

    solution = asyncio.run(
        AiSolver(MissingFinalLatexProvider()).solve(b"image")  # type: ignore[arg-type]
    )
    assert solution.final_answer_latex == r"\\sum U=0"


def test_solver_lowers_confidence_when_unit_check_fails() -> None:
    class FailedUnitProvider:
        name = "test"
        model = "test"

        async def generate(self, request):
            if request.structured_output_name == "circuit_extraction":
                return AiProviderResult(
                    valid_extraction_payload(), self.name, self.model, 0.01
                )
            payload = valid_solution_payload()
            payload["confidence"] = "high"
            payload["unit_check"]["passed"] = False
            return AiProviderResult(payload, self.name, self.model, 0.01)

    solution = asyncio.run(
        AiSolver(FailedUnitProvider()).solve(b"image")  # type: ignore[arg-type]
    )
    assert solution.confidence == "low"
    assert any("单位检查未通过" in item for item in solution.uncertain)


def test_solver_does_not_expose_unverified_ai_result_as_high_confidence() -> None:
    class OverconfidentProvider:
        name = "test"
        model = "test"

        async def generate(self, request):
            if request.structured_output_name == "circuit_extraction":
                return AiProviderResult(
                    valid_extraction_payload(), self.name, self.model, 0.01
                )
            payload = valid_solution_payload()
            payload["confidence"] = "high"
            payload["steps"][0]["latex"] = r"U=12\text{V}"
            return AiProviderResult(payload, self.name, self.model, 0.01)

    solution = asyncio.run(
        AiSolver(OverconfidentProvider()).solve(b"image")  # type: ignore[arg-type]
    )
    assert solution.confidence == "medium"


def test_consistency_check_detects_step_final_conflict() -> None:
    class ConflictingProvider:
        name = "test"
        model = "test"

        async def generate(self, request):
            if request.structured_output_name == "circuit_extraction":
                return AiProviderResult(
                    valid_extraction_payload(), self.name, self.model, 0.01
                )
            payload = valid_solution_payload()
            payload["final_answer"] = "U = 12 V。"
            payload["final_answer_latex"] = r"U=12\text{V}"
            payload["steps"][0]["latex"] = r"U=10\text{V}"
            return AiProviderResult(payload, self.name, self.model, 0.01)

    solution = asyncio.run(
        AiSolver(ConflictingProvider()).solve(b"image")  # type: ignore[arg-type]
    )
    assert solution.confidence == "low"
    assert any("步骤与最终答案数值不一致" in item for item in solution.uncertain)


def provider_request():
    from app.providers.base import AiProviderRequest

    return AiProviderRequest(
        image_bytes=b"jpeg bytes",
        system_prompt="system",
        user_prompt="user",
        json_schema=AiSolution.model_json_schema(),
    )
