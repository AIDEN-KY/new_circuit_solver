from __future__ import annotations

import logging
import json
import re

from pydantic import ValidationError

from .models import AiSolution, AskResponse, ChatMessage, ChatResponse, CircuitExtraction
from .providers.base import AiProvider, AiProviderRequest
from .providers.errors import AiProviderResponseError


LOGGER = logging.getLogger(__name__)

EXTRACTION_SYSTEM_PROMPT = (
    "你是电工学题目识图员。必须使用中文，只做忠实识别，不进行求解、不猜答案。"
    "逐字读取题干，列出所有元件标签、数值、单位、节点、支路方向、受控关系和开关/去源变化。"
    "connections 必须用明确的节点—元件—节点描述连接关系；无法看清的内容写入 uncertain。"
    "若题目包含原图和变换后的子图，必须分别识别两张图，并把变换后子图的实际连线作为权威依据："
    "电源符号消失但两端仍由连续导线相连表示短路；只有导线中断或端点悬空才表示开路。"
)
EXTRACTION_USER_PROMPT = (
    "请把图片中的电工学题转换为给定JSON结构。problem_text保留完整题意；"
    "target_variables只列题目要求的量；components逐个记录元件；given_conditions不得遗漏；"
    "diagram_notes说明多个子图、箭头、极性和输出端。禁止计算最终答案。"
)
SOLUTION_SYSTEM_PROMPT = (
    "你是严谨的大学电工学教师。输入是已经从图片提取的结构化题目。"
    "必须仅依据该结构求解，不得添加不存在的参数。先重建拓扑并选择定理，先符号推导再代入数值，"
    "最后用独立代入、极性、数量级和单位检查复核。必须使用中文。每个包含公式或计算的步骤都要"
    "填写latex；latex只写源码，不要Markdown围栏。content中的物理量、变量、数值、单位及短公式"
    "必须用单个美元符号包裹为行内LaTeX，例如 $R_1=20\\Omega$，中文说明保留普通文本。"
    "最终答案、final_answer_latex和最后计算步骤"
    "必须完全一致。条件不足时不得编造数值，应降低confidence并写入uncertain。"
    "处理线性电路去源或置零时：独立理想电压源置零等效为短路，独立理想电流源置零等效为开路，"
    "受控源不能关闭；若题目给出变换后的目标子图，必须优先按该子图的实际导线连接求解。"
    "不得仅凭‘除去’二字把仍由导线连接的支路误判为断路。"
    "若题目给出原输出并询问移除某个独立源后的输出，必须写出带参考极性的叠加关系："
    "原输出=保留源产生的输出+被移除源单独产生的输出，所以保留源输出=原输出-被移除源贡献。"
    "被移除源的贡献必须在其余独立源置零后计算，并按题目所标正负极性决定代数符号；"
    "不得把该贡献不经符号判断直接加到原输出上。"
)


class AiSolver:
    """先识图、后推理，并对结果做服务端一致性检查。"""

    def __init__(self, provider: AiProvider) -> None:
        self._provider = provider

    async def solve(self, image_bytes: bytes) -> AiSolution:
        extraction = await self._extract(image_bytes)
        solution = await self._reason(extraction)
        return self._normalize_and_check(solution, extraction)

    async def follow_up(
        self,
        image_bytes: bytes,
        original_response: AskResponse,
        messages: list[ChatMessage],
        message: str,
    ) -> ChatResponse:
        """结合原图、原答案和用户补充信息继续答疑。"""
        history = [item.model_dump() for item in messages[-20:]]
        user_prompt = (
            "请围绕同一道题回答用户的新问题。重新核对随附原图；如果用户补充或纠正了模糊条件，"
            "应以用户的新信息为准并说明它对结论的影响。不要声称看到了图片中不存在的内容。"
            "回答应简洁但包含必要推导。所有物理量、变量、数值、单位和公式都用单个美元符号"
            "包裹为行内LaTeX，例如 $I=0.4\\,\\mathrm{A}$。\n\n"
            f"原求解结果：\n{original_response.model_dump_json(indent=2)}\n\n"
            f"此前对话：\n{json.dumps(history, ensure_ascii=False)}\n\n"
            f"用户新问题：\n{message}"
        )
        result = await self._provider.generate(
            AiProviderRequest(
                image_bytes=image_bytes,
                system_prompt=(
                    "你是严谨、耐心的大学电工学教师。使用中文回答，只讨论当前题目。"
                    "若信息仍不足，明确指出需要用户补充什么，不得编造条件。"
                ),
                user_prompt=user_prompt,
                json_schema=ChatResponse.model_json_schema(),
                structured_output_name="circuit_follow_up",
                # 追问强调快速澄清；关闭思考模式可避免推理 token 吞完输出额度。
                reasoning_effort="none",
                max_output_tokens=4096,
            )
        )
        self._log_result("follow_up", result.provider, result.model, result.elapsed_seconds)
        try:
            return ChatResponse.model_validate(result.payload)
        except ValidationError as error:
            raise AiProviderResponseError("AI追问结果不符合结构化协议") from error

    async def _extract(self, image_bytes: bytes) -> CircuitExtraction:
        result = await self._provider.generate(
            AiProviderRequest(
                image_bytes=image_bytes,
                system_prompt=EXTRACTION_SYSTEM_PROMPT,
                user_prompt=EXTRACTION_USER_PROMPT,
                json_schema=CircuitExtraction.model_json_schema(),
                structured_output_name="circuit_extraction",
                reasoning_effort="none",
                max_output_tokens=2048,
            )
        )
        self._log_result("extract", result.provider, result.model, result.elapsed_seconds)
        try:
            return CircuitExtraction.model_validate(result.payload)
        except ValidationError as error:
            raise AiProviderResponseError("AI识图结果不符合结构化协议") from error

    async def _reason(self, extraction: CircuitExtraction) -> AiSolution:
        user_prompt = (
            "求解下面的结构化电路题，并严格按JSON Schema输出。最多5个必要步骤，每步content"
            "不超过100个汉字。逐项回答target_variables；列方程后必须重新代入验证，禁止最终字段"
            "与步骤出现不同数值。\n\n结构化题目：\n"
            + extraction.model_dump_json(indent=2)
        )
        result = await self._provider.generate(
            AiProviderRequest(
                image_bytes=None,
                system_prompt=SOLUTION_SYSTEM_PROMPT,
                user_prompt=user_prompt,
                json_schema=AiSolution.model_json_schema(),
                structured_output_name="circuit_solution",
                reasoning_effort="low",
                max_output_tokens=16384,
            )
        )
        self._log_result("reason", result.provider, result.model, result.elapsed_seconds)
        try:
            return AiSolution.model_validate(result.payload)
        except ValidationError as error:
            raise AiProviderResponseError(
                "AI推理结果不符合Circuit Solver响应协议"
            ) from error

    @staticmethod
    def _log_result(stage: str, provider: str, model: str, elapsed: float) -> None:
        LOGGER.info(
            "AI stage=%s provider=%s model=%s elapsed=%.3fs",
            stage,
            provider,
            model,
            elapsed,
        )

    def _normalize_and_check(
        self, solution: AiSolution, extraction: CircuitExtraction
    ) -> AiSolution:
        uncertain = list(solution.uncertain)
        confidence = "medium" if solution.confidence == "high" else solution.confidence

        if extraction.uncertain:
            uncertain.append(
                "识图阶段存在未确认内容：" + "；".join(extraction.uncertain)
            )

        if not solution.final_answer_latex.strip():
            for step in reversed(solution.steps):
                latex = step.latex.strip()
                if latex:
                    solution = solution.model_copy(
                        update={"final_answer_latex": latex}
                    )
                    break

        combined_final = solution.final_answer + " " + solution.final_answer_latex
        missing_targets = [
            target
            for target in extraction.target_variables
            if not self._contains_target(combined_final, target)
        ]
        if missing_targets:
            confidence = "low"
            uncertain.append("最终答案未逐项回答：" + "、".join(missing_targets))

        conflicts = self._find_step_conflicts(solution, extraction.target_variables)
        if conflicts:
            confidence = "low"
            uncertain.append("步骤与最终答案数值不一致：" + "、".join(conflicts))

        if not solution.unit_check.passed:
            confidence = "low"
            uncertain.append("模型的单位检查未通过，请人工核对计算过程和最终答案。")

        deduplicated = list(dict.fromkeys(item for item in uncertain if item.strip()))
        return solution.model_copy(
            update={"confidence": confidence, "uncertain": deduplicated}
        )

    @staticmethod
    def _canonical_math(value: str) -> str:
        value = re.sub(r"_\{([^{}]+)\}", r"_\1", value)
        value = value.replace("\\", "")
        # 目标量可能被 OCR 写成 Uab、U_ab 或 U_{ab}，匹配时忽略排版下标。
        return re.sub(r"[^A-Za-z0-9]+", "", value).lower()

    @classmethod
    def _contains_target(cls, text: str, target: str) -> bool:
        canonical_target = cls._canonical_math(target)
        canonical_text = cls._canonical_math(text)
        return bool(canonical_target) and canonical_target in canonical_text

    @classmethod
    def _find_step_conflicts(
        cls, solution: AiSolution, targets: list[str]
    ) -> list[str]:
        final_text = solution.final_answer + " " + solution.final_answer_latex
        step_text = " ".join(
            step.content + " " + step.latex for step in solution.steps
        )
        conflicts: list[str] = []
        for target in targets:
            final_value = cls._last_assigned_number(final_text, target)
            step_value = cls._last_assigned_number(step_text, target)
            if final_value is None or step_value is None:
                continue
            tolerance = max(1e-6, abs(final_value) * 1e-3)
            if abs(final_value - step_value) > tolerance:
                conflicts.append(target)
        return conflicts

    @staticmethod
    def _last_assigned_number(text: str, target: str) -> float | None:
        normalized = re.sub(r"_\{([^{}]+)\}", r"_\1", text)
        normalized_target = re.sub(r"_\{([^{}]+)\}", r"_\1", target)
        pattern = re.compile(
            rf"(?<![A-Za-z0-9_]){re.escape(normalized_target)}"
            rf"(?![A-Za-z0-9_])\s*(?:=|≈|\\approx)\s*([^,，;；。\n]+)",
            re.IGNORECASE,
        )
        matches = list(pattern.finditer(normalized))
        if not matches:
            return None
        numbers = re.findall(r"[-+]?\d+(?:\.\d+)?", matches[-1].group(1))
        if not numbers:
            return None
        try:
            return float(numbers[-1])
        except ValueError:
            return None
