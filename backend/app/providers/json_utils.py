from __future__ import annotations

import json
from typing import Any

from .errors import AiProviderResponseError


def parse_json_object(value: Any) -> dict[str, Any]:
    if isinstance(value, dict):
        return dict(value)
    if not isinstance(value, str) or not value.strip():
        raise AiProviderResponseError("AI Provider 未返回 JSON 内容")
    try:
        decoded = json.loads(value)
    except json.JSONDecodeError as error:
        raise AiProviderResponseError("AI Provider 返回的内容不是有效 JSON") from error
    if not isinstance(decoded, dict):
        raise AiProviderResponseError("AI Provider 返回的 JSON 顶层必须是对象")
    return decoded

