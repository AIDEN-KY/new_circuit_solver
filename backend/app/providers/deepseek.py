from __future__ import annotations

import base64
from time import perf_counter

import httpx

from .base import AiProvider, AiProviderRequest, AiProviderResult
from .errors import (
    AiProviderConfigurationError,
    AiProviderError,
    AiProviderResponseError,
    AiProviderTimeoutError,
)
from .json_utils import parse_json_object


class DeepSeekVisionProvider(AiProvider):
    """通过 DeepSeek Responses API 调用支持图片输入的视觉模型。"""

    def __init__(
        self,
        base_url: str,
        api_key: str,
        model: str,
        timeout_seconds: float,
        max_output_tokens: int = 1024,
        reasoning_effort: str = "none",
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self._base_url = base_url.rstrip("/")
        self._api_key = api_key
        self._model = model
        self._timeout_seconds = timeout_seconds
        self._max_output_tokens = max_output_tokens
        self._reasoning_effort = reasoning_effort
        self._transport = transport

    @property
    def name(self) -> str:
        return "deepseek"

    @property
    def model(self) -> str:
        return self._model

    async def generate(self, request: AiProviderRequest) -> AiProviderResult:
        if not self._base_url or not self._api_key or not self._model:
            raise AiProviderConfigurationError(
                "DeepSeek Provider 需要配置 AI_API_BASE_URL、AI_API_KEY 和 AI_MODEL"
            )
        content: list[dict[str, object]] = [
            {"type": "input_text", "text": request.user_prompt}
        ]
        if request.image_bytes is not None:
            data_uri = "data:image/jpeg;base64," + base64.b64encode(
                request.image_bytes
            ).decode("ascii")
            content.append(
                {
                    "type": "input_image",
                    "image_url": data_uri,
                    "detail": "original",
                }
            )
        payload = {
            "model": self._model,
            "instructions": request.system_prompt,
            "input": [
                {
                    "role": "user",
                    "content": content,
                }
            ],
            "temperature": 0,
            "max_output_tokens": request.max_output_tokens
            or self._max_output_tokens,
            "reasoning": {
                "effort": request.reasoning_effort or self._reasoning_effort
            },
            "text": {
                "format": {
                    "type": "json_schema",
                    "name": request.structured_output_name,
                    "schema": request.json_schema,
                }
            },
        }
        started = perf_counter()
        try:
            async with httpx.AsyncClient(
                timeout=self._timeout_seconds,
                transport=self._transport,
            ) as client:
                response = await client.post(
                    f"{self._base_url}/responses",
                    headers={"Authorization": f"Bearer {self._api_key}"},
                    json=payload,
                )
                response.raise_for_status()
            response_body = response.json()
            if response_body.get("status") == "incomplete":
                raise AiProviderResponseError(
                    "DeepSeek 输出被截断："
                    f"{response_body.get('incomplete_details')}"
                )
            content = self._extract_output_text(response_body)
            parsed = parse_json_object(content)
        except httpx.TimeoutException as error:
            raise AiProviderTimeoutError("DeepSeek 视觉模型响应超时") from error
        except httpx.HTTPStatusError as error:
            status = error.response.status_code
            raise AiProviderError(f"DeepSeek API 调用失败（HTTP {status}）") from error
        except httpx.HTTPError as error:
            raise AiProviderError("无法连接 DeepSeek API") from error
        except (KeyError, TypeError, ValueError) as error:
            raise AiProviderError("DeepSeek API 返回了无法读取的响应") from error
        return AiProviderResult(
            payload=parsed,
            provider=self.name,
            model=self.model,
            elapsed_seconds=perf_counter() - started,
            usage=(
                response_body.get("usage")
                if isinstance(response_body.get("usage"), dict)
                else None
            ),
        )

    @staticmethod
    def _extract_output_text(body: dict[str, object]) -> str:
        output = body.get("output")
        if not isinstance(output, list):
            raise AiProviderResponseError("DeepSeek 响应缺少 output")
        for item in output:
            if not isinstance(item, dict) or item.get("type") != "message":
                continue
            content = item.get("content")
            if not isinstance(content, list):
                continue
            for part in content:
                if (
                    isinstance(part, dict)
                    and part.get("type") == "output_text"
                    and isinstance(part.get("text"), str)
                ):
                    return part["text"]
        status = body.get("status", "unknown")
        error = body.get("error")
        incomplete = body.get("incomplete_details")
        details = error if error else incomplete
        raise AiProviderResponseError(
            f"DeepSeek 响应中没有结构化文本结果（status={status}, details={details}）"
        )
