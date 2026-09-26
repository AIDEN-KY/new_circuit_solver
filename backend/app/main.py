from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException

from .ai_solver import AiSolver
from .config import Settings
from .image_processing import ImageProcessor, InvalidImageError
from .models import AskRequest, AskResponse
from .repository import QuestionRepository
from .service import AskService, VisionSolver
from .providers import AiProviderError, create_ai_provider


def create_app(
    settings: Settings | None = None,
    ai_client: VisionSolver | None = None,
) -> FastAPI:
    resolved = settings or Settings.from_env()
    repository = QuestionRepository(resolved.database_path)
    service = AskService(
        repository=repository,
        image_processor=ImageProcessor(resolved.max_image_bytes),
        ai_client=ai_client or AiSolver(create_ai_provider(resolved)),
        match_threshold=resolved.library_match_threshold,
    )

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        repository.initialize()
        yield

    app = FastAPI(
        title="Circuit Solver API",
        version="0.1.0",
        lifespan=lifespan,
    )

    @app.post("/api/v1/ask", response_model=AskResponse)
    async def ask(request: AskRequest) -> AskResponse:
        try:
            return await service.ask(request)
        except InvalidImageError as error:
            raise HTTPException(status_code=400, detail=str(error)) from error
        except AiProviderError as error:
            raise HTTPException(status_code=503, detail=str(error)) from error

    return app


app = create_app()
