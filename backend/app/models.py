from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


class CropBox(BaseModel):
    model_config = ConfigDict(extra="forbid")

    x: int = Field(ge=0)
    y: int = Field(ge=0)
    w: int = Field(gt=0)
    h: int = Field(gt=0)


class AskRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    image_base64: str = Field(min_length=32)
    crop_box: CropBox
    rotation_degrees: int = 0
    subject: Literal["circuit"] = "circuit"

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
