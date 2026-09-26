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


class OllamaProvider(AiProvider):
    def __init__(
        self,
        base_url: str,
        model: str,
        timeout_seconds: float,
        max_output_tokens: int = 1024,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self._base_url = base_url.rstrip("/")
        self._model = model
        self._timeout_seconds = timeout_seconds
        self._max_output_tokens = max_output_tokens
        self._transport = transport

    @property
    def name(self) -> str:
        return "ollama"

    @property
    def model(self) -> str:
        return self._model

    async def generate(self, request: AiProviderRequest) -> AiProviderResult:
        if not self._model:
            raise AiProviderConfigurationError("服务端尚未配置 AI_MODEL")
        user_message: dict[str, object] = {
            "role": "user",
            "content": request.user_prompt,
        }
        if request.image_bytes is not None:
            user_message["images"] = [
                base64.b64encode(request.image_bytes).decode("ascii")
            ]
        payload = {
            "model": self._model,
            "stream": False,
            "format": request.json_schema,
            "options": {
                "temperature": 0,
                "num_predict": request.max_output_tokens
                or self._max_output_tokens,
            },
            "messages": [
                {"role": "system", "content": request.system_prompt},
                user_message,
            ],
        }
        started = perf_counter()
        try:
            async with httpx.AsyncClient(
                timeout=self._timeout_seconds,
                transport=self._transport,
            ) as client:
                response = await client.post(f"{self._base_url}/api/chat", json=payload)
                response.raise_for_status()
            content = response.json().get("message", {}).get("content")
            parsed = parse_json_object(content)
        except httpx.TimeoutException as error:
            raise AiProviderTimeoutError("本地 AI 模型响应超时") from error
        except httpx.HTTPError as error:
            raise AiProviderError("无法调用本地 Ollama 服务") from error
        except (TypeError, ValueError, KeyError) as error:
            raise AiProviderError("Ollama 返回了无法读取的响应") from error
        return AiProviderResult(
            payload=parsed,
            provider=self.name,
            model=self.model,
            elapsed_seconds=perf_counter() - started,
        )
