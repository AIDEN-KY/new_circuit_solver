from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


BACKEND_DIR = Path(__file__).resolve().parents[1]


def _resolve_path(value: str) -> Path:
    path = Path(value)
    return path if path.is_absolute() else BACKEND_DIR / path


@dataclass(frozen=True, slots=True)
class Settings:
    """从环境变量读取服务配置，避免把密钥和机器路径写进代码。"""

    database_path: Path
    ai_provider: str
    ai_model: str
    ai_timeout_seconds: float
    ai_max_output_tokens: int
    ollama_base_url: str
    ai_api_base_url: str
    ai_api_key: str
    library_match_threshold: float
    max_image_bytes: int
    ai_reasoning_effort: str = "none"

    @classmethod
    def from_env(cls) -> "Settings":
        threshold = float(os.getenv("LIBRARY_MATCH_THRESHOLD", "0.92"))
        if not 0 <= threshold <= 1:
            raise ValueError("LIBRARY_MATCH_THRESHOLD 必须在 0 到 1 之间")
        reasoning_effort = os.getenv("AI_REASONING_EFFORT", "none").strip().lower()
        if reasoning_effort not in {"none", "low", "high", "max"}:
            raise ValueError("AI_REASONING_EFFORT 只支持 none、low、high、max")
        return cls(
            database_path=_resolve_path(
                os.getenv("CIRCUIT_DATABASE_PATH", "data/circuit_solver.db")
            ),
            ai_provider=os.getenv("AI_PROVIDER", "ollama").strip().lower(),
            ai_model=os.getenv("AI_MODEL", os.getenv("OLLAMA_MODEL", "")).strip(),
            ai_timeout_seconds=float(os.getenv("AI_TIMEOUT_SECONDS", "25")),
            ai_max_output_tokens=int(os.getenv("AI_MAX_OUTPUT_TOKENS", "1024")),
            ollama_base_url=os.getenv(
                "OLLAMA_BASE_URL", "http://127.0.0.1:11434"
            ).rstrip("/"),
            ai_api_base_url=os.getenv("AI_API_BASE_URL", "").rstrip("/"),
            ai_api_key=os.getenv("AI_API_KEY", ""),
            library_match_threshold=threshold,
            max_image_bytes=int(os.getenv("MAX_IMAGE_BYTES", str(8 * 1024 * 1024))),
            ai_reasoning_effort=reasoning_effort,
        )
