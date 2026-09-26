from __future__ import annotations

from typing import Protocol
from uuid import uuid4

from .image_processing import ImageProcessor
from .models import AiSolution, AskRequest, AskResponse, ChatRequest, ChatResponse
from .repository import QuestionRepository


class VisionSolver(Protocol):
    async def solve(self, image_bytes: bytes) -> AiSolution: ...

    async def follow_up(
        self,
        image_bytes: bytes,
        original_response: AskResponse,
        messages: list,
        message: str,
    ) -> ChatResponse: ...


class AskService:
    def __init__(
        self,
        repository: QuestionRepository,
        image_processor: ImageProcessor,
        ai_client: VisionSolver,
        match_threshold: float,
    ) -> None:
        self._repository = repository
        self._image_processor = image_processor
        self._ai_client = ai_client
        self._match_threshold = match_threshold

    async def ask(self, request: AskRequest) -> AskResponse:
        request_id = f"req_{uuid4().hex[:16]}"
        image_bytes = self._image_processor.prepare(request)
        fingerprint = self._image_processor.fingerprint(image_bytes)
        match, similar = self._repository.search(
            fingerprint, self._match_threshold
        )
        if match is not None:
            confidence = "high" if match.similarity >= 0.97 else "medium"
            return match.response.model_copy(
                update={
                    "request_id": request_id,
                    "source": "library",
                    "confidence": confidence,
                    "similar_questions": similar,
                }
            )

        solution = await self._ai_client.solve(image_bytes)
        return AskResponse(
            request_id=request_id,
            source="ai",
            similar_questions=similar,
            **solution.model_dump(),
        )

    async def chat(self, request: ChatRequest) -> ChatResponse:
        image_bytes = self._image_processor.prepare(request)
        return await self._ai_client.follow_up(
            image_bytes=image_bytes,
            original_response=request.original_response,
            messages=request.messages,
            message=request.message,
        )
