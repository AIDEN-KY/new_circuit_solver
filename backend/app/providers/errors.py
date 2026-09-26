class AiProviderError(RuntimeError):
    """Provider 层统一异常，不向核心业务泄漏厂商异常类型。"""


class AiProviderConfigurationError(AiProviderError):
    """Provider 配置缺失或不受支持。"""


class AiProviderTimeoutError(AiProviderError):
    """模型调用超过配置的最大等待时间。"""


class AiProviderResponseError(AiProviderError):
    """模型响应不是有效的结构化结果。"""

