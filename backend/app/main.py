from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.responses import FileResponse

from .account_repository import (
    Account,
    AccountExistsError,
    AccountRepository,
    InsufficientCreditsError,
    InvalidCredentialsError,
    InvalidSessionError,
    AccountNotFoundError,
    DuplicateGrantError,
)
from .admin_repository import (
    AdminDisabledError,
    AdminRepository,
    InvalidAdminCredentialsError,
    InvalidAdminSessionError,
)
from .ai_solver import AiSolver
from .config import BACKEND_DIR, Settings
from .image_processing import ImageProcessor, InvalidImageError
from .models import (
    AccountActivity,
    AdminGrantRequest,
    AdminLoginRequest,
    AdminLoginResponse,
    AdminUserSummary,
    AccountProfile,
    AskRequest,
    AskResponse,
    AuthResponse,
    ChatRequest,
    ChatResponse,
    CredentialsRequest,
)
from .repository import QuestionRepository
from .service import AskService, VisionSolver
from .providers import AiProviderError, create_ai_provider


def _is_ai_configured(settings: Settings) -> bool:
    if not settings.ai_model:
        return False
    if settings.ai_provider == "ollama":
        return bool(settings.ollama_base_url)
    if settings.ai_provider in {"deepseek", "openai_compatible"}:
        return bool(settings.ai_api_base_url and settings.ai_api_key)
    return False


def create_app(
    settings: Settings | None = None,
    ai_client: VisionSolver | None = None,
) -> FastAPI:
    resolved = settings or Settings.from_env()
    repository = QuestionRepository(resolved.database_path)
    accounts = AccountRepository(
        resolved.database_path,
        initial_free_uses=resolved.initial_free_uses,
        solve_price_fen=resolved.solve_price_fen,
        session_days=resolved.session_days,
    )
    admins = AdminRepository(
        resolved.database_path,
        username=resolved.admin_username,
        password=resolved.admin_password,
        session_days=resolved.session_days,
    )
    service = AskService(
        repository=repository,
        image_processor=ImageProcessor(resolved.max_image_bytes),
        ai_client=ai_client or AiSolver(create_ai_provider(resolved)),
        match_threshold=resolved.library_match_threshold,
    )

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        repository.initialize()
        accounts.initialize()
        admins.initialize()
        yield

    app = FastAPI(
        title="Circuit Solver API",
        version="0.5.0",
        lifespan=lifespan,
    )

    def account_profile(account: Account) -> AccountProfile:
        return AccountProfile(
            id=account.id,
            username=account.username,
            free_uses_remaining=account.free_uses_remaining,
            balance_fen=account.balance_fen,
            solve_price_fen=resolved.solve_price_fen,
        )

    def bearer_token(authorization: str | None) -> str:
        if authorization is None or not authorization.startswith("Bearer "):
            raise HTTPException(status_code=401, detail="请先登录")
        token = authorization[7:].strip()
        if not token:
            raise HTTPException(status_code=401, detail="请先登录")
        return token

    async def current_account(
        authorization: str | None = Header(default=None),
    ) -> Account | None:
        if not resolved.auth_required and not authorization:
            return None
        try:
            return accounts.authenticate(bearer_token(authorization))
        except InvalidSessionError as error:
            raise HTTPException(status_code=401, detail=str(error)) from error

    def admin_bearer(authorization: str | None) -> str:
        if authorization is None or not authorization.startswith("Bearer "):
            raise HTTPException(status_code=401, detail="请先登录后台")
        token = authorization[7:].strip()
        if not token:
            raise HTTPException(status_code=401, detail="请先登录后台")
        return token

    async def current_admin(
        authorization: str | None = Header(default=None),
    ) -> str:
        try:
            return admins.authenticate(admin_bearer(authorization))
        except InvalidAdminSessionError as error:
            raise HTTPException(status_code=401, detail=str(error)) from error

    @app.get("/api/v1/health")
    async def health() -> dict[str, object]:
        """供测试版 App 检测服务状态；不返回 API Key 等敏感配置。"""
        return {
            "status": "ok",
            "version": app.version,
            "ai_provider": resolved.ai_provider,
            "ai_model": resolved.ai_model,
            "ai_configured": _is_ai_configured(resolved),
            "library_questions": repository.count_publishable(),
            "auth_required": resolved.auth_required,
        }

    @app.post("/api/v1/auth/register", response_model=AuthResponse, status_code=201)
    async def register(request: CredentialsRequest) -> AuthResponse:
        try:
            session = accounts.register(request.username, request.password)
        except AccountExistsError as error:
            raise HTTPException(status_code=409, detail=str(error)) from error
        return AuthResponse(
            access_token=session.token,
            account=account_profile(session.account),
        )

    @app.post("/api/v1/auth/login", response_model=AuthResponse)
    async def login(request: CredentialsRequest) -> AuthResponse:
        try:
            session = accounts.login(request.username, request.password)
        except InvalidCredentialsError as error:
            raise HTTPException(status_code=401, detail=str(error)) from error
        return AuthResponse(
            access_token=session.token,
            account=account_profile(session.account),
        )

    @app.get("/api/v1/account/me", response_model=AccountProfile)
    async def me(
        account: Account | None = Depends(current_account),
    ) -> AccountProfile:
        if account is None:
            raise HTTPException(status_code=401, detail="请先登录")
        return account_profile(account)

    @app.get("/api/v1/account/activities", response_model=list[AccountActivity])
    async def account_activities(
        account: Account | None = Depends(current_account),
    ) -> list[AccountActivity]:
        if account is None:
            raise HTTPException(status_code=401, detail="请先登录")
        return [
            AccountActivity(
                id=entry.id,
                event_type=entry.event_type,
                free_uses_delta=entry.free_uses_delta,
                balance_fen_delta=entry.balance_fen_delta,
                created_at=entry.created_at,
            )
            for entry in accounts.list_ledger(account.id)
        ]

    @app.post("/api/v1/auth/logout", status_code=204)
    async def logout(authorization: str | None = Header(default=None)) -> None:
        token = bearer_token(authorization)
        try:
            accounts.authenticate(token)
        except InvalidSessionError as error:
            raise HTTPException(status_code=401, detail=str(error)) from error
        accounts.logout(token)

    @app.get("/admin", include_in_schema=False)
    async def admin_page() -> FileResponse:
        return FileResponse(BACKEND_DIR / "admin" / "index.html")

    @app.post("/api/v1/admin/login", response_model=AdminLoginResponse)
    async def admin_login(request: AdminLoginRequest) -> AdminLoginResponse:
        try:
            session = admins.login(request.username, request.password)
        except AdminDisabledError as error:
            raise HTTPException(status_code=503, detail=str(error)) from error
        except InvalidAdminCredentialsError as error:
            raise HTTPException(status_code=401, detail=str(error)) from error
        return AdminLoginResponse(access_token=session.token, username=session.username)

    @app.post("/api/v1/admin/logout", status_code=204)
    async def admin_logout(authorization: str | None = Header(default=None)) -> None:
        admins.logout(admin_bearer(authorization))

    @app.get("/api/v1/admin/users", response_model=list[AdminUserSummary])
    async def admin_users(
        keyword: str = "",
        _: str = Depends(current_admin),
    ) -> list[AdminUserSummary]:
        return [
            AdminUserSummary(
                id=item.id,
                username=item.username,
                free_uses_remaining=item.free_uses_remaining,
                created_at=item.created_at,
            )
            for item in accounts.search_users(keyword)
        ]

    @app.post("/api/v1/admin/users/{user_id}/grant-uses", response_model=AccountProfile)
    async def admin_grant_uses(
        user_id: str,
        request: AdminGrantRequest,
        operator: str = Depends(current_admin),
    ) -> AccountProfile:
        try:
            account = accounts.grant_uses(
                user_id,
                request.uses,
                operator=operator,
                reference_id=request.reference_id,
                note=request.note,
            )
        except AccountNotFoundError as error:
            raise HTTPException(status_code=404, detail=str(error)) from error
        except DuplicateGrantError as error:
            raise HTTPException(status_code=409, detail=str(error)) from error
        except ValueError as error:
            raise HTTPException(status_code=400, detail=str(error)) from error
        return account_profile(account)

    @app.get("/api/v1/admin/users/{user_id}/activities", response_model=list[AccountActivity])
    async def admin_user_activities(
        user_id: str,
        _: str = Depends(current_admin),
    ) -> list[AccountActivity]:
        try:
            accounts.get_account(user_id)
        except AccountNotFoundError as error:
            raise HTTPException(status_code=404, detail=str(error)) from error
        return [
            AccountActivity(
                id=entry.id,
                event_type=entry.event_type,
                free_uses_delta=entry.free_uses_delta,
                balance_fen_delta=entry.balance_fen_delta,
                created_at=entry.created_at,
            )
            for entry in accounts.list_ledger(user_id)
        ]

    @app.post("/api/v1/ask", response_model=AskResponse)
    async def ask(
        request: AskRequest,
        account: Account | None = Depends(current_account),
    ) -> AskResponse:
        reservation = None
        try:
            if account is not None:
                reservation = accounts.reserve_usage(account.id)
            response = await service.ask(request)
            if reservation is not None:
                accounts.commit_usage(reservation.id)
            return response
        except InsufficientCreditsError as error:
            raise HTTPException(status_code=402, detail=str(error)) from error
        except InvalidImageError as error:
            if reservation is not None:
                accounts.refund_usage(reservation.id)
            raise HTTPException(status_code=400, detail=str(error)) from error
        except AiProviderError as error:
            if reservation is not None:
                accounts.refund_usage(reservation.id)
            raise HTTPException(status_code=503, detail=str(error)) from error
        except Exception:
            if reservation is not None:
                accounts.refund_usage(reservation.id)
            raise

    @app.post("/api/v1/chat", response_model=ChatResponse)
    async def chat(
        request: ChatRequest,
        _: Account | None = Depends(current_account),
    ) -> ChatResponse:
        try:
            return await service.chat(request)
        except InvalidImageError as error:
            raise HTTPException(status_code=400, detail=str(error)) from error
        except AiProviderError as error:
            raise HTTPException(status_code=503, detail=str(error)) from error

    return app


app = create_app()
