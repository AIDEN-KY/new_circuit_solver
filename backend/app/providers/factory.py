from __future__ import annotations

from ..config import Settings
from .base import AiProvider
from .deepseek import DeepSeekVisionProvider
from .errors import AiProviderConfigurationError
from .ollama import OllamaProvider
from .openai_compatible import OpenAiCompatibleVisionProvider


def create_ai_provider(settings: Settings) -> AiProvider:
    if settings.ai_provider == "ollama":
        return OllamaProvider(
            base_url=settings.ollama_base_url,
            model=settings.ai_model,
            timeout_seconds=settings.ai_timeout_seconds,
            max_output_tokens=settings.ai_max_output_tokens,
        )
    if settings.ai_provider == "openai_compatible":
        return OpenAiCompatibleVisionProvider(
            base_url=settings.ai_api_base_url,
            api_key=settings.ai_api_key,
            model=settings.ai_model,
            timeout_seconds=settings.ai_timeout_seconds,
            max_output_tokens=settings.ai_max_output_tokens,
        )
    if settings.ai_provider == "deepseek":
        return DeepSeekVisionProvider(
            base_url=settings.ai_api_base_url,
            api_key=settings.ai_api_key,
            model=settings.ai_model,
            timeout_seconds=settings.ai_timeout_seconds,
            max_output_tokens=settings.ai_max_output_tokens,
            reasoning_effort=settings.ai_reasoning_effort,
        )
    raise AiProviderConfigurationError(
        f"不支持的 AI_PROVIDER：{settings.ai_provider}"
    )
