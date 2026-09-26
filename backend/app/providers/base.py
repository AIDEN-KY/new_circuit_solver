from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True, slots=True)
class AiProviderRequest:
    """与具体厂商无关的视觉模型请求。"""

    image_bytes: bytes | None
    system_prompt: str
    user_prompt: str
    json_schema: dict[str, Any]
    structured_output_name: str = "circuit_solution"
    reasoning_effort: str | None = None
    max_output_tokens: int | None = None


@dataclass(frozen=True, slots=True)
class AiProviderResult:
    """Provider 解码后的统一结果与调用指标。"""

    payload: dict[str, Any]
    provider: str
    model: str
    elapsed_seconds: float
    usage: dict[str, Any] | None = None


class AiProvider(ABC):
    """所有本地或云端视觉模型 Provider 必须实现的接口。"""

    @property
    @abstractmethod
    def name(self) -> str:
        raise NotImplementedError

    @property
    @abstractmethod
    def model(self) -> str:
        raise NotImplementedError

    @abstractmethod
    async def generate(self, request: AiProviderRequest) -> AiProviderResult:
        """发送图片和 Prompt，并返回已解析的结构化 JSON。"""
        raise NotImplementedError
