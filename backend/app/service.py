from __future__ import annotations

from typing import Protocol
from uuid import uuid4

from .image_processing import ImageProcessor
from .models import AiSolution, AskRequest, AskResponse, ChatRequest, ChatResponse
from .spice_validator import validate_spice_netlist


class VisionSolver(Protocol):
    async def solve(self, image_bytes: bytes | None, user_context: str = "") -> AiSolution: ...

    async def follow_up(
        self,
        image_bytes: bytes | None,
        original_response: AskResponse,
        messages: list,
        message: str,
    ) -> ChatResponse: ...


class AskService:
    def __init__(
        self,
        image_processor: ImageProcessor,
        ai_client: VisionSolver,
    ) -> None:
        self._image_processor = image_processor
        self._ai_client = ai_client

    async def ask(self, request: AskRequest) -> AskResponse:
        request_id = f"req_{uuid4().hex[:16]}"
        image_bytes = (
            self._image_processor.prepare(request)
            if request.image_base64.strip()
            else None
        )
        context = getattr(request, "description", "") or getattr(
            request, "clarification_text", ""
        )
        if context:
            solution = await self._ai_client.solve(image_bytes, context)
        else:
            solution = await self._ai_client.solve(image_bytes)
        checked = validate_spice_netlist(solution.netlist)
        if not checked.validation_passed:
            solution = solution.model_copy(
                update={"netlist": checked, "uncertain": solution.uncertain + checked.validation_messages}
            )
        else:
            solution = solution.model_copy(update={"netlist": checked})
        return AskResponse(
            request_id=request_id,
            source="ai",
            similar_questions=[],
            **solution.model_dump(),
        )

    async def chat(self, request: ChatRequest) -> ChatResponse:
        image_bytes = (
            self._image_processor.prepare(request)
            if request.image_base64.strip()
            else None
        )
        result = await self._ai_client.follow_up(
            image_bytes=image_bytes,
            original_response=request.original_response,
            messages=request.messages,
            message=request.message,
        )
        if result.intent != "modify_circuit" or result.updated_netlist is None:
            return result
        checked = validate_spice_netlist(result.updated_netlist)
        if not checked.validation_passed:
            return result.model_copy(update={"updated_netlist": checked})
        recalculated = None
        solver = getattr(self._ai_client, "solve_from_netlist", None)
        if solver is not None:
            solution = await solver(checked.raw, request.message)
            recalculated_netlist = validate_spice_netlist(solution.netlist)
            solution = solution.model_copy(update={"netlist": recalculated_netlist})
            recalculated = AskResponse(
                request_id=f"req_{uuid4().hex[:16]}",
                source="ai",
                similar_questions=[],
                **solution.model_dump(),
            )
        return result.model_copy(
            update={"updated_netlist": checked, "recalculated_response": recalculated}
        )
