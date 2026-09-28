from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator
import re


class CropBox(BaseModel):
    model_config = ConfigDict(extra="forbid")

    x: int = Field(ge=0)
    y: int = Field(ge=0)
    w: int = Field(gt=0)
    h: int = Field(gt=0)


class AskRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    image_base64: str = ""
    crop_box: CropBox = Field(default_factory=lambda: CropBox(x=0, y=0, w=1, h=1))
    rotation_degrees: int = 0
    subject: Literal["circuit"] = "circuit"
    input_mode: Literal["photo", "description", "interactive"] = "photo"
    description: str = Field(default="", max_length=8000)
    clarification_text: str = Field(default="", max_length=8000)
    client_request_id: str | None = Field(default=None, min_length=8, max_length=80)

    @field_validator("rotation_degrees")
    @classmethod
    def validate_rotation(cls, value: int) -> int:
        normalized = value % 360
        if normalized not in {0, 90, 180, 270}:
            raise ValueError("rotation_degrees 只支持 0、90、180、270")
        return normalized


class SolutionStep(BaseModel):
    model_config = ConfigDict(extra="forbid")

    step_number: int = Field(ge=1)
    title: str = Field(min_length=1)
    content: str = Field(
        min_length=1,
        description="中文说明；物理量、数字、单位和短公式必须用 $...$ 包裹",
    )
    latex: str = ""


class UnitCheck(BaseModel):
    model_config = ConfigDict(extra="forbid")

    expected_unit: str = ""
    actual_unit: str = ""
    passed: bool
    note: str = ""


class SimilarQuestion(BaseModel):
    model_config = ConfigDict(extra="forbid")

    question_id: str = Field(min_length=1)
    title: str = Field(min_length=1)
    similarity: float = Field(ge=0, le=1)


class CircuitComponent(BaseModel):
    """第一阶段从图片中识别出的单个电路元件。"""

    model_config = ConfigDict(extra="forbid")

    label: str = Field(min_length=1)
    component_type: str = Field(min_length=1)
    value: str = ""
    unit: str = ""


class CircuitExtraction(BaseModel):
    """只描述题目图片，不进行计算，供第二阶段推理使用。"""

    model_config = ConfigDict(extra="forbid")

    problem_text: str = Field(min_length=1)
    target_variables: list[str] = Field(min_length=1)
    components: list[CircuitComponent] = Field(default_factory=list)
    connections: list[str] = Field(default_factory=list)
    given_conditions: list[str] = Field(default_factory=list)
    diagram_notes: list[str] = Field(default_factory=list)
    uncertain: list[str] = Field(default_factory=list)


class SpiceNetlist(BaseModel):
    """AI 生成、服务端校验后绑定到当前题目的 SPICE 网表。"""

    model_config = ConfigDict(extra="forbid")

    raw: str = ""
    elements: list[str] = Field(default_factory=list)
    validation_passed: bool = False
    validation_messages: list[str] = Field(default_factory=list)


class AiSolution(BaseModel):
    """AI 必须返回的结构；服务端补充 request_id 和 source。"""

    model_config = ConfigDict(extra="forbid")

    confidence: Literal["high", "medium", "low"]
    final_answer: str = Field(min_length=1)
    final_answer_latex: str = ""
    steps: list[SolutionStep] = Field(min_length=1)
    knowledge_points: list[str] = Field(default_factory=list)
    unit_check: UnitCheck
    uncertain: list[str] = Field(default_factory=list)
    disclaimer: str = "本结果由 AI 辅助生成，请核对关键条件。"
    netlist: SpiceNetlist = Field(default_factory=SpiceNetlist)


class AskResponse(AiSolution):
    request_id: str = Field(min_length=1)
    source: Literal["library", "ai"]
    similar_questions: list[SimilarQuestion] = Field(default_factory=list)


class ChatMessage(BaseModel):
    model_config = ConfigDict(extra="forbid")

    role: Literal["user", "assistant"]
    content: str = Field(min_length=1, max_length=4000)


class ChatRequest(AskRequest):
    """围绕一次识图结果继续追问，并重新附带原题图片供模型核对。"""

    original_response: AskResponse
    messages: list[ChatMessage] = Field(default_factory=list, max_length=20)
    message: str = Field(min_length=1, max_length=2000)


class ChatResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    answer: str = Field(
        min_length=1,
        description="中文回答；物理量、数字、单位和公式必须用 $...$ 包裹",
    )
    intent: Literal["answer", "modify_circuit"] = "answer"
    updated_netlist: SpiceNetlist | None = None
    recalculated_response: AskResponse | None = None


class CredentialsRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    username: str = Field(min_length=3, max_length=32)
    password: str = Field(min_length=8, max_length=128)

    @field_validator("username")
    @classmethod
    def validate_username(cls, value: str) -> str:
        normalized = value.strip()
        if not re.fullmatch(r"[A-Za-z0-9_\-\u4e00-\u9fff]+", normalized):
            raise ValueError("用户名只能包含中英文、数字、下划线和短横线")
        return normalized


class AccountProfile(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    username: str
    free_uses_remaining: int = Field(ge=0)
    balance_fen: int = Field(ge=0)
    solve_price_fen: int = Field(gt=0)
    status: Literal["active", "disabled"] = "active"


class AccountActivity(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: int = Field(ge=1)
    event_type: Literal[
        "register_bonus",
        "solve_reserved",
        "solve_committed",
        "solve_refunded",
        "recharge",
        "adjustment",
    ]
    free_uses_delta: int
    balance_fen_delta: int
    created_at: int = Field(gt=0)


class AuthResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    access_token: str
    token_type: Literal["bearer"] = "bearer"
    account: AccountProfile


class AdminLoginRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    username: str = Field(min_length=1, max_length=64)
    password: str = Field(min_length=1, max_length=128)


class AdminLoginResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    access_token: str
    username: str


class AdminGrantRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    uses: int = Field(gt=0, le=100000)
    reference_id: str = Field(min_length=1, max_length=128)
    note: str = Field(default="", max_length=500)


class AdminAdjustUsesRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    delta: int = Field(ge=-100000, le=100000)
    reference_id: str = Field(min_length=1, max_length=128)
    note: str = Field(min_length=1, max_length=500)

    @field_validator("delta")
    @classmethod
    def validate_delta(cls, value: int) -> int:
        if value == 0:
            raise ValueError("调整次数不能为0")
        return value


class AdminUserStatusRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: Literal["active", "disabled"]
    note: str = Field(min_length=1, max_length=500)


class AdminUserSummary(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    username: str
    free_uses_remaining: int
    created_at: int
    status: Literal["active", "disabled"] = "active"


class PublicAppConfig(BaseModel):
    model_config = ConfigDict(extra="forbid")

    announcement_enabled: bool
    announcement_title: str
    announcement_message: str
    maintenance_mode: bool
    maintenance_message: str
    support_message: str
    qq_group: str
    initial_free_uses: int = Field(ge=0, le=100)
    min_supported_version: str
    latest_version: str
    download_url: str
    revision: int = Field(ge=1)
    updated_at: int = Field(ge=0)


class AdminAppConfigUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    announcement_enabled: bool
    announcement_title: str = Field(max_length=100)
    announcement_message: str = Field(max_length=1000)
    maintenance_mode: bool
    maintenance_message: str = Field(min_length=1, max_length=500)
    support_message: str = Field(min_length=1, max_length=500)
    qq_group: str = Field(max_length=30)
    initial_free_uses: int = Field(ge=0, le=100)
    min_supported_version: str = Field(min_length=1, max_length=30)
    latest_version: str = Field(min_length=1, max_length=30)
    download_url: str = Field(max_length=500)
