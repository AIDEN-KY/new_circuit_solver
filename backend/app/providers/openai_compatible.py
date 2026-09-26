from __future__ import annotations

import base64
from time import perf_counter

import httpx

from .base import AiProvider, AiProviderRequest, AiProviderResult
from .errors import (
    AiProviderConfigurationError,
    AiProviderError,
    AiProviderTimeoutError,
)
from .json_utils import parse_json_object


class OpenAiCompatibleVisionProvider(AiProvider):
    """云端扩展位，仅适用于支持图片和 json_schema 的兼容接口。"""

    def __init__(
        self,
        base_url: str,
        api_key: str,
        model: str,
        timeout_seconds: float,
        max_output_tokens: int = 1024,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self._base_url = base_url.rstrip("/")
        self._api_key = api_key
        self._model = model
        self._timeout_seconds = timeout_seconds
        self._max_output_tokens = max_output_tokens
        self._transport = transport

    @property
    def name(self) -> str:
        return "openai_compatible"

    @property
    def model(self) -> str:
        return self._model

    async def generate(self, request: AiProviderRequest) -> AiProviderResult:
        if not self._base_url or not self._api_key or not self._model:
            raise AiProviderConfigurationError(
                "云端 Provider 需要配置 AI_API_BASE_URL、AI_API_KEY 和 AI_MODEL"
            )
        content: list[dict[str, object]] = [
            {"type": "text", "text": request.user_prompt}
        ]
        if request.image_bytes is not None:
            data_uri = "data:image/jpeg;base64," + base64.b64encode(
                request.image_bytes
            ).decode("ascii")
            content.append(
                {"type": "image_url", "image_url": {"url": data_uri}}
            )
        payload = {
            "model": self._model,
            "messages": [
                {"role": "system", "content": request.system_prompt},
                {
                    "role": "user",
                    "content": content,
                },
            ],
            "temperature": 0,
            "max_tokens": request.max_output_tokens or self._max_output_tokens,
            "response_format": {
                "type": "json_schema",
                "json_schema": {
                    "name": request.structured_output_name,
                    "strict": True,
                    "schema": request.json_schema,
                },
            },
        }
        started = perf_counter()
        try:
            async with httpx.AsyncClient(
                timeout=self._timeout_seconds,
                transport=self._transport,
            ) as client:
                response = await client.post(
                    f"{self._base_url}/chat/completions",
                    headers={"Authorization": f"Bearer {self._api_key}"},
                    json=payload,
                )
                response.raise_for_status()
            content = response.json()["choices"][0]["message"]["content"]
            parsed = parse_json_object(content)
        except httpx.TimeoutException as error:
            raise AiProviderTimeoutError("云端 AI 模型响应超时") from error
        except httpx.HTTPError as error:
            raise AiProviderError("无法调用云端 AI 服务") from error
        except (IndexError, KeyError, TypeError, ValueError) as error:
            raise AiProviderError("云端 AI 返回了无法读取的响应") from error
        return AiProviderResult(
            payload=parsed,
            provider=self.name,
            model=self.model,
            elapsed_seconds=perf_counter() - started,
        )
