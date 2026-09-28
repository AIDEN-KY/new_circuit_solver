from __future__ import annotations

from contextlib import asynccontextmanager
from dataclasses import asdict

from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse

from .account_repository import (
    Account,
    AccountExistsError,
    AccountNotFoundError,
    AccountRepository,
    DuplicateGrantError,
    InsufficientCreditsError,
    InvalidCredentialsError,
    InvalidSessionError,
)
from .admin_repository import (
    AdminDisabledError,
    AdminRepository,
    InvalidAdminCredentialsError,
    InvalidAdminSessionError,
)
from .ai_solver import AiSolver
from .app_config_repository import AppConfig, AppConfigRepository
from .config import BACKEND_DIR, Settings
from .image_processing import ImageProcessor, InvalidImageError
from .models import (
    AccountActivity,
    AccountProfile,
    AdminAdjustUsesRequest,
    AdminAppConfigUpdate,
    AdminGrantRequest,
    AdminLoginRequest,
    AdminLoginResponse,
    AdminUserStatusRequest,
    AdminUserSummary,
    AskRequest,
    AskResponse,
    AuthResponse,
    ChatRequest,
    ChatResponse,
    CredentialsRequest,
    PublicAppConfig,
)
from .providers import AiProviderError, create_ai_provider
from .rate_limit import (
    AccountBusyError,
    RateLimitExceeded,
    SlidingWindowLimiter,
    SolveConcurrencyGuard,
)
from .service import AskService, VisionSolver
from .solve_request_repository import SolveRequestInProgress, SolveRequestRepository


def _is_ai_configured(settings: Settings) -> bool:
    if not settings.ai_model:
        return False
    if settings.ai_provider == "ollama":
        return bool(settings.ollama_base_url)
    if settings.ai_provider in {"deepseek", "openai_compatible"}:
        return bool(settings.ai_api_base_url and settings.ai_api_key)
    return False


def _version_tuple(value: str) -> tuple[int, ...]:
    try:
        return tuple(int(part) for part in value.split("+")[0].split("."))
    except ValueError:
        return (0,)


def create_app(
    settings: Settings | None = None,
    ai_client: VisionSolver | None = None,
) -> FastAPI:
    resolved = settings or Settings.from_env()
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
    configs = AppConfigRepository(
        resolved.database_path,
        default_initial_free_uses=resolved.initial_free_uses,
    )
    solve_requests = SolveRequestRepository(resolved.database_path)
    service = AskService(
        image_processor=ImageProcessor(resolved.max_image_bytes),
        ai_client=ai_client or AiSolver(create_ai_provider(resolved)),
    )
    limiter = SlidingWindowLimiter()
    solve_guard = SolveConcurrencyGuard(resolved.max_concurrent_solves)

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        accounts.initialize()
        admins.initialize()
        configs.initialize()
        solve_requests.initialize()
        yield

    app = FastAPI(title="Circuit Solver API", version="0.7.0", lifespan=lifespan)

    @app.middleware("http")
    async def enforce_request_size(request: Request, call_next):
        raw_length = request.headers.get("content-length")
        if raw_length and raw_length.isdigit() and int(raw_length) > resolved.max_request_bytes:
            return JSONResponse(status_code=413, content={"detail": "请求内容过大"})
        # Content-Length 可能缺失或被伪造，仍以实际接收字节数作为最终边界。
        body = await request.body()
        if len(body) > resolved.max_request_bytes:
            return JSONResponse(status_code=413, content={"detail": "请求内容过大"})
        return await call_next(request)

    def request_ip(request: Request) -> str:
        if resolved.trust_cloudflare_headers:
            forwarded = request.headers.get("cf-connecting-ip", "").strip()
            if forwarded:
                return forwarded
        return request.client.host if request.client else "unknown"

    def account_profile(account: Account) -> AccountProfile:
        return AccountProfile(
            id=account.id,
            username=account.username,
            free_uses_remaining=account.free_uses_remaining,
            balance_fen=account.balance_fen,
            solve_price_fen=resolved.solve_price_fen,
            status=account.status,
        )

    def public_config(value: AppConfig) -> PublicAppConfig:
        return PublicAppConfig(**asdict(value))

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

    def enforce_runtime_policy(app_version: str | None) -> AppConfig:
        config = configs.get()
        if config.maintenance_mode:
            raise HTTPException(status_code=503, detail=config.maintenance_message)
        if app_version and _version_tuple(app_version) < _version_tuple(config.min_supported_version):
            raise HTTPException(status_code=426, detail="当前版本过低，请更新后继续使用")
        return config

    @app.get("/api/v1/health")
    async def health() -> dict[str, object]:
        return {
            "status": "ok",
            "version": app.version,
            "ai_provider": resolved.ai_provider,
            "ai_model": resolved.ai_model,
            "ai_configured": _is_ai_configured(resolved),
            "library_questions": 0,
            "auth_required": resolved.auth_required,
        }

    @app.get("/api/v1/app-config", response_model=PublicAppConfig)
    async def get_app_config() -> PublicAppConfig:
        return public_config(configs.get())

    @app.post("/api/v1/auth/register", response_model=AuthResponse, status_code=201)
    async def register(request: CredentialsRequest, http_request: Request) -> AuthResponse:
        try:
            await limiter.check(
                f"register:{request_ip(http_request)}", limit=5, window_seconds=86400
            )
            session = accounts.register(
                request.username,
                request.password,
                initial_free_uses=configs.get().initial_free_uses,
            )
        except RateLimitExceeded as error:
            raise HTTPException(status_code=429, detail=str(error)) from error
        except AccountExistsError as error:
            raise HTTPException(status_code=409, detail=str(error)) from error
        return AuthResponse(access_token=session.token, account=account_profile(session.account))

    @app.post("/api/v1/auth/login", response_model=AuthResponse)
    async def login(request: CredentialsRequest, http_request: Request) -> AuthResponse:
        try:
            await limiter.check(
                f"login:{request_ip(http_request)}", limit=10, window_seconds=900
            )
            session = accounts.login(request.username, request.password)
        except RateLimitExceeded as error:
            raise HTTPException(status_code=429, detail=str(error)) from error
        except InvalidCredentialsError as error:
            raise HTTPException(status_code=401, detail=str(error)) from error
        return AuthResponse(access_token=session.token, account=account_profile(session.account))

    @app.get("/api/v1/account/me", response_model=AccountProfile)
    async def me(account: Account | None = Depends(current_account)) -> AccountProfile:
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

    if resolved.admin_routes_enabled:
        _register_admin_routes(
            app, accounts, admins, configs, account_profile, public_config, current_admin,
            admin_bearer,
        )

    @app.post("/api/v1/ask", response_model=AskResponse)
    async def ask(
        request: AskRequest,
        account: Account | None = Depends(current_account),
        x_app_version: str | None = Header(default=None, alias="X-App-Version"),
    ) -> AskResponse:
        enforce_runtime_policy(x_app_version)
        account_key = account.id if account is not None else "anonymous"
        try:
            await limiter.check(f"ask:{account_key}", limit=10, window_seconds=3600)
            async with solve_guard.acquire(account_key):
                client_id = request.client_request_id
                if account is not None and client_id:
                    cached = solve_requests.completed_response(account.id, client_id)
                    if cached is not None:
                        return AskResponse.model_validate_json(cached)
                    solve_requests.start(account.id, client_id)
                reservation = None
                try:
                    if account is not None:
                        reservation = accounts.reserve_usage(account.id)
                    response = await service.ask(request)
                    if reservation is not None:
                        accounts.commit_usage(reservation.id)
                    if account is not None and client_id:
                        solve_requests.complete(account.id, client_id, response.model_dump_json())
                    return response
                except Exception:
                    if reservation is not None:
                        accounts.refund_usage(reservation.id)
                    if account is not None and client_id:
                        solve_requests.fail(account.id, client_id)
                    raise
        except (RateLimitExceeded, AccountBusyError, SolveRequestInProgress) as error:
            raise HTTPException(status_code=429, detail=str(error)) from error
        except InsufficientCreditsError as error:
            raise HTTPException(status_code=402, detail=str(error)) from error
        except InvalidImageError as error:
            raise HTTPException(status_code=400, detail=str(error)) from error
        except AiProviderError as error:
            raise HTTPException(status_code=503, detail=str(error)) from error

    @app.post("/api/v1/chat", response_model=ChatResponse)
    async def chat(
        request: ChatRequest,
        account: Account | None = Depends(current_account),
        x_app_version: str | None = Header(default=None, alias="X-App-Version"),
    ) -> ChatResponse:
        enforce_runtime_policy(x_app_version)
        account_key = account.id if account is not None else "anonymous"
        try:
            await limiter.check(f"chat:{account_key}", limit=20, window_seconds=3600)
            async with solve_guard.acquire(account_key):
                return await service.chat(request)
        except (RateLimitExceeded, AccountBusyError) as error:
            raise HTTPException(status_code=429, detail=str(error)) from error
        except InvalidImageError as error:
            raise HTTPException(status_code=400, detail=str(error)) from error
        except AiProviderError as error:
            raise HTTPException(status_code=503, detail=str(error)) from error

    return app


def _register_admin_routes(
    app: FastAPI,
    accounts: AccountRepository,
    admins: AdminRepository,
    configs: AppConfigRepository,
    account_profile,
    public_config,
    current_admin,
    admin_bearer,
) -> None:
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
        keyword: str = "", _: str = Depends(current_admin)
    ) -> list[AdminUserSummary]:
        return [
            AdminUserSummary(
                id=item.id, username=item.username,
                free_uses_remaining=item.free_uses_remaining,
                created_at=item.created_at, status=item.status,
            )
            for item in accounts.search_users(keyword)
        ]

    @app.post("/api/v1/admin/users/{user_id}/grant-uses", response_model=AccountProfile)
    async def admin_grant_uses(
        user_id: str, request: AdminGrantRequest,
        operator: str = Depends(current_admin),
    ) -> AccountProfile:
        return await _adjust_user(
            accounts, configs, account_profile, user_id, request.uses,
            request.reference_id, request.note or "兼容接口人工发放", operator,
        )

    @app.post("/api/v1/admin/users/{user_id}/adjust-uses", response_model=AccountProfile)
    async def admin_adjust_uses(
        user_id: str, request: AdminAdjustUsesRequest,
        operator: str = Depends(current_admin),
    ) -> AccountProfile:
        return await _adjust_user(
            accounts, configs, account_profile, user_id, request.delta,
            request.reference_id, request.note, operator,
        )

    @app.post("/api/v1/admin/users/{user_id}/status", response_model=AccountProfile)
    async def admin_set_user_status(
        user_id: str, request: AdminUserStatusRequest,
        operator: str = Depends(current_admin),
    ) -> AccountProfile:
        try:
            before = accounts.get_account(user_id)
            account = accounts.set_status(user_id, request.status)
            configs.record_audit(
                operator=operator, action="set_user_status", target=user_id,
                before={"status": before.status, "note": request.note},
                after={"status": account.status},
            )
            return account_profile(account)
        except AccountNotFoundError as error:
            raise HTTPException(status_code=404, detail=str(error)) from error

    @app.get("/api/v1/admin/users/{user_id}/activities", response_model=list[AccountActivity])
    async def admin_user_activities(
        user_id: str, _: str = Depends(current_admin)
    ) -> list[AccountActivity]:
        try:
            accounts.get_account(user_id)
        except AccountNotFoundError as error:
            raise HTTPException(status_code=404, detail=str(error)) from error
        return [
            AccountActivity(
                id=entry.id, event_type=entry.event_type,
                free_uses_delta=entry.free_uses_delta,
                balance_fen_delta=entry.balance_fen_delta,
                created_at=entry.created_at,
            )
            for entry in accounts.list_ledger(user_id)
        ]

    @app.get("/api/v1/admin/config", response_model=PublicAppConfig)
    async def admin_get_config(_: str = Depends(current_admin)) -> PublicAppConfig:
        return public_config(configs.get())

    @app.put("/api/v1/admin/config", response_model=PublicAppConfig)
    async def admin_update_config(
        request: AdminAppConfigUpdate,
        operator: str = Depends(current_admin),
    ) -> PublicAppConfig:
        current = configs.get()
        value = AppConfig(
            **request.model_dump(), revision=current.revision, updated_at=current.updated_at
        )
        return public_config(configs.update(value, operator=operator))


async def _adjust_user(
    accounts: AccountRepository,
    configs: AppConfigRepository,
    account_profile,
    user_id: str,
    delta: int,
    reference_id: str,
    note: str,
    operator: str,
) -> AccountProfile:
    try:
        before = accounts.get_account(user_id)
        account = accounts.adjust_uses(
            user_id, delta, operator=operator,
            reference_id=reference_id, note=note,
        )
        configs.record_audit(
            operator=operator, action="adjust_uses", target=user_id,
            before={"uses": before.free_uses_remaining},
            after={"uses": account.free_uses_remaining},
        )
        return account_profile(account)
    except AccountNotFoundError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error
    except DuplicateGrantError as error:
        raise HTTPException(status_code=409, detail=str(error)) from error
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


app = create_app()
