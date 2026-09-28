from __future__ import annotations

import hashlib
import hmac
import secrets
import sqlite3
import time
import uuid
from dataclasses import dataclass
from pathlib import Path


class AccountExistsError(ValueError):
    pass


class InvalidCredentialsError(ValueError):
    pass


class InvalidSessionError(ValueError):
    pass


class InsufficientCreditsError(ValueError):
    pass


class AccountNotFoundError(ValueError):
    pass


class DuplicateGrantError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class Account:
    id: str
    username: str
    free_uses_remaining: int
    balance_fen: int
    status: str = "active"


@dataclass(frozen=True, slots=True)
class Session:
    token: str
    account: Account


@dataclass(frozen=True, slots=True)
class UsageReservation:
    id: str
    user_id: str
    source: str
    amount_fen: int


@dataclass(frozen=True, slots=True)
class AccountLedgerEntry:
    id: int
    event_type: str
    free_uses_delta: int
    balance_fen_delta: int
    created_at: int


@dataclass(frozen=True, slots=True)
class AccountSummary:
    id: str
    username: str
    free_uses_remaining: int
    created_at: int
    status: str = "active"


class AccountRepository:
    """账号、会话和额度账本。金额始终以分存储，避免浮点误差。"""

    _password_iterations = 310_000

    def __init__(
        self,
        database_path: Path,
        *,
        initial_free_uses: int,
        solve_price_fen: int,
        session_days: int,
    ) -> None:
        self._database_path = database_path
        self._initial_free_uses = initial_free_uses
        self._solve_price_fen = solve_price_fen
        self._session_seconds = session_days * 24 * 60 * 60

    def initialize(self) -> None:
        self._database_path.parent.mkdir(parents=True, exist_ok=True)
        with self._connect() as connection:
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS users (
                    id TEXT PRIMARY KEY,
                    username TEXT NOT NULL UNIQUE COLLATE NOCASE,
                    password_hash TEXT NOT NULL,
                    free_uses_remaining INTEGER NOT NULL CHECK(free_uses_remaining >= 0),
                    balance_fen INTEGER NOT NULL DEFAULT 0 CHECK(balance_fen >= 0),
                    created_at INTEGER NOT NULL,
                    status TEXT NOT NULL DEFAULT 'active'
                );
                CREATE TABLE IF NOT EXISTS sessions (
                    token_hash TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    expires_at INTEGER NOT NULL,
                    created_at INTEGER NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);
                CREATE TABLE IF NOT EXISTS usage_reservations (
                    id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL REFERENCES users(id),
                    source TEXT NOT NULL CHECK(source IN ('free', 'balance')),
                    amount_fen INTEGER NOT NULL,
                    status TEXT NOT NULL CHECK(status IN ('reserved', 'committed', 'refunded')),
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL
                );
                CREATE TABLE IF NOT EXISTS account_ledger (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id TEXT NOT NULL REFERENCES users(id),
                    event_type TEXT NOT NULL,
                    free_uses_delta INTEGER NOT NULL DEFAULT 0,
                    balance_fen_delta INTEGER NOT NULL DEFAULT 0,
                    reference_id TEXT NOT NULL DEFAULT '',
                    created_at INTEGER NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_ledger_user ON account_ledger(user_id, id);
                CREATE TABLE IF NOT EXISTS manual_grants (
                    id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL REFERENCES users(id),
                    uses INTEGER NOT NULL CHECK(uses > 0),
                    operator TEXT NOT NULL,
                    reference_id TEXT NOT NULL UNIQUE,
                    note TEXT NOT NULL DEFAULT '',
                    created_at INTEGER NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_manual_grants_user
                ON manual_grants(user_id, created_at);
                CREATE TABLE IF NOT EXISTS manual_adjustments (
                    id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL REFERENCES users(id),
                    delta INTEGER NOT NULL CHECK(delta != 0),
                    operator TEXT NOT NULL,
                    reference_id TEXT NOT NULL UNIQUE,
                    note TEXT NOT NULL,
                    created_at INTEGER NOT NULL
                );
                """
            )
            columns = {
                row["name"]
                for row in connection.execute("PRAGMA table_info(users)").fetchall()
            }
            if "status" not in columns:
                connection.execute(
                    "ALTER TABLE users ADD COLUMN status TEXT NOT NULL DEFAULT 'active'"
                )
        # 服务进程异常退出时，尚未完成的预占请求不应永久消耗用户额度。
        with self._connect() as connection:
            pending = connection.execute(
                "SELECT id FROM usage_reservations WHERE status = 'reserved'"
            ).fetchall()
        for row in pending:
            self.refund_usage(row["id"])

    def register(
        self, username: str, password: str, *, initial_free_uses: int | None = None
    ) -> Session:
        user_id = uuid.uuid4().hex
        now = int(time.time())
        granted_uses = self._initial_free_uses if initial_free_uses is None else max(0, initial_free_uses)
        try:
            with self._connect() as connection:
                connection.execute(
                    """
                    INSERT INTO users(id, username, password_hash, free_uses_remaining,
                                      balance_fen, created_at)
                    VALUES (?, ?, ?, ?, 0, ?)
                    """,
                    (
                        user_id,
                        username,
                        self._hash_password(password),
                        granted_uses,
                        now,
                    ),
                )
                connection.execute(
                    """
                    INSERT INTO account_ledger(
                        user_id, event_type, free_uses_delta, reference_id, created_at
                    ) VALUES (?, 'register_bonus', ?, ?, ?)
                    """,
                    (user_id, granted_uses, user_id, now),
                )
        except sqlite3.IntegrityError as error:
            raise AccountExistsError("该用户名已被注册") from error
        return self._create_session(user_id)

    def login(self, username: str, password: str) -> Session:
        with self._connect() as connection:
            row = connection.execute(
                "SELECT id, password_hash, status FROM users WHERE username = ? COLLATE NOCASE",
                (username,),
            ).fetchone()
        if row is None or not self._verify_password(password, row["password_hash"]):
            raise InvalidCredentialsError("用户名或密码错误")
        if row["status"] != "active":
            raise InvalidCredentialsError("账号已被停用，请联系管理员")
        return self._create_session(row["id"])

    def authenticate(self, token: str) -> Account:
        token_hash = self._token_hash(token)
        now = int(time.time())
        with self._connect() as connection:
            row = connection.execute(
                """
                SELECT u.id, u.username, u.free_uses_remaining, u.balance_fen, u.status
                FROM sessions s
                JOIN users u ON u.id = s.user_id
                WHERE s.token_hash = ? AND s.expires_at > ?
                """,
                (token_hash, now),
            ).fetchone()
        if row is None:
            raise InvalidSessionError("登录已失效，请重新登录")
        if row["status"] != "active":
            raise InvalidSessionError("账号已被停用，请联系管理员")
        return self._account_from_row(row)

    def logout(self, token: str) -> None:
        with self._connect() as connection:
            connection.execute(
                "DELETE FROM sessions WHERE token_hash = ?", (self._token_hash(token),)
            )

    def list_ledger(self, user_id: str, *, limit: int = 50) -> list[AccountLedgerEntry]:
        safe_limit = min(max(limit, 1), 100)
        with self._connect() as connection:
            rows = connection.execute(
                """
                SELECT id, event_type, free_uses_delta, balance_fen_delta, created_at
                FROM account_ledger
                WHERE user_id = ?
                ORDER BY id DESC
                LIMIT ?
                """,
                (user_id, safe_limit),
            ).fetchall()
        return [
            AccountLedgerEntry(
                id=int(row["id"]),
                event_type=row["event_type"],
                free_uses_delta=int(row["free_uses_delta"]),
                balance_fen_delta=int(row["balance_fen_delta"]),
                created_at=int(row["created_at"]),
            )
            for row in rows
        ]

    def search_users(self, keyword: str, *, limit: int = 50) -> list[AccountSummary]:
        """仅供受保护的 Admin 接口查询用户，不返回密码或余额敏感字段。"""
        value = keyword.strip()
        safe_limit = min(max(limit, 1), 100)
        pattern = f"%{value}%"
        with self._connect() as connection:
            rows = connection.execute(
                """SELECT id, username, free_uses_remaining, created_at, status FROM users
                   WHERE id LIKE ? OR username LIKE ? COLLATE NOCASE
                   ORDER BY created_at DESC LIMIT ?""",
                (pattern, pattern, safe_limit),
            ).fetchall()
        return [
            AccountSummary(
                id=row["id"],
                username=row["username"],
                free_uses_remaining=int(row["free_uses_remaining"]),
                created_at=int(row["created_at"]),
                status=row["status"],
            )
            for row in rows
        ]

    def get_account(self, user_id: str) -> Account:
        with self._connect() as connection:
            row = connection.execute(
                "SELECT id, username, free_uses_remaining, balance_fen, status FROM users WHERE id = ?",
                (user_id,),
            ).fetchone()
        if row is None:
            raise AccountNotFoundError("未找到该用户ID")
        return self._account_from_row(row)

    def grant_uses(
        self,
        user_id: str,
        uses: int,
        *,
        operator: str,
        reference_id: str,
        note: str = "",
    ) -> Account:
        """兼容旧接口；新后台统一使用 adjust_uses。"""
        if uses <= 0:
            raise ValueError("发放次数必须大于0")
        operator = operator.strip()
        reference_id = reference_id.strip()
        if not operator or not reference_id:
            raise ValueError("操作人和业务流水号不能为空")
        now = int(time.time())
        grant_id = uuid.uuid4().hex
        connection = self._connect()
        try:
            connection.execute("BEGIN IMMEDIATE")
            exists = connection.execute(
                "SELECT 1 FROM users WHERE id = ?", (user_id,)
            ).fetchone()
            if exists is None:
                raise AccountNotFoundError("未找到该用户ID")
            connection.execute(
                """
                INSERT INTO manual_grants(
                    id, user_id, uses, operator, reference_id, note, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (grant_id, user_id, uses, operator, reference_id, note.strip(), now),
            )
            connection.execute(
                """
                UPDATE users
                SET free_uses_remaining = free_uses_remaining + ?
                WHERE id = ?
                """,
                (uses, user_id),
            )
            connection.execute(
                """
                INSERT INTO account_ledger(
                    user_id, event_type, free_uses_delta, reference_id, created_at
                ) VALUES (?, 'adjustment', ?, ?, ?)
                """,
                (user_id, uses, reference_id, now),
            )
            row = connection.execute(
                """
                SELECT id, username, free_uses_remaining, balance_fen
                FROM users WHERE id = ?
                """,
                (user_id,),
            ).fetchone()
            connection.commit()
            return self._account_from_row(row)
        except sqlite3.IntegrityError as error:
            connection.rollback()
            if "manual_grants.reference_id" in str(error):
                raise DuplicateGrantError("该业务流水号已经处理，禁止重复发放") from error
            raise
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()

    def adjust_uses(
        self,
        user_id: str,
        delta: int,
        *,
        operator: str,
        reference_id: str,
        note: str,
    ) -> Account:
        if delta == 0:
            raise ValueError("调整次数不能为0")
        if not operator.strip() or not reference_id.strip() or not note.strip():
            raise ValueError("操作人、业务流水号和备注不能为空")
        now = int(time.time())
        connection = self._connect()
        try:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute(
                "SELECT free_uses_remaining FROM users WHERE id = ?", (user_id,)
            ).fetchone()
            if row is None:
                raise AccountNotFoundError("未找到该用户ID")
            if int(row["free_uses_remaining"]) + delta < 0:
                raise ValueError("扣减后剩余次数不能小于0")
            connection.execute(
                """INSERT INTO manual_adjustments(
                       id, user_id, delta, operator, reference_id, note, created_at
                   ) VALUES (?, ?, ?, ?, ?, ?, ?)""",
                (
                    uuid.uuid4().hex, user_id, delta, operator.strip(),
                    reference_id.strip(), note.strip(), now,
                ),
            )
            connection.execute(
                "UPDATE users SET free_uses_remaining = free_uses_remaining + ? WHERE id = ?",
                (delta, user_id),
            )
            connection.execute(
                """INSERT INTO account_ledger(
                       user_id, event_type, free_uses_delta, reference_id, created_at
                   ) VALUES (?, 'adjustment', ?, ?, ?)""",
                (user_id, delta, reference_id.strip(), now),
            )
            result = connection.execute(
                """SELECT id, username, free_uses_remaining, balance_fen, status
                   FROM users WHERE id = ?""",
                (user_id,),
            ).fetchone()
            connection.commit()
            return self._account_from_row(result)
        except sqlite3.IntegrityError as error:
            connection.rollback()
            if "reference_id" in str(error):
                raise DuplicateGrantError("该业务流水号已经处理，禁止重复调整") from error
            raise
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()

    def set_status(self, user_id: str, status: str) -> Account:
        if status not in {"active", "disabled"}:
            raise ValueError("不支持的账号状态")
        with self._connect() as connection:
            cursor = connection.execute(
                "UPDATE users SET status = ? WHERE id = ?", (status, user_id)
            )
            if cursor.rowcount == 0:
                raise AccountNotFoundError("未找到该用户ID")
            if status == "disabled":
                connection.execute("DELETE FROM sessions WHERE user_id = ?", (user_id,))
            row = connection.execute(
                """SELECT id, username, free_uses_remaining, balance_fen, status
                   FROM users WHERE id = ?""",
                (user_id,),
            ).fetchone()
        return self._account_from_row(row)

    def reserve_usage(self, user_id: str) -> UsageReservation:
        reservation_id = uuid.uuid4().hex
        now = int(time.time())
        connection = self._connect()
        try:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute(
                "SELECT free_uses_remaining, balance_fen, status FROM users WHERE id = ?",
                (user_id,),
            ).fetchone()
            if row is None:
                raise InvalidSessionError("账号不存在")
            if row["status"] != "active":
                raise InvalidSessionError("账号已被停用，请联系管理员")
            if row["free_uses_remaining"] > 0:
                source, amount_fen = "free", 0
                connection.execute(
                    "UPDATE users SET free_uses_remaining = free_uses_remaining - 1 WHERE id = ?",
                    (user_id,),
                )
                free_delta, balance_delta = -1, 0
            elif row["balance_fen"] >= self._solve_price_fen:
                source, amount_fen = "balance", self._solve_price_fen
                connection.execute(
                    "UPDATE users SET balance_fen = balance_fen - ? WHERE id = ?",
                    (amount_fen, user_id),
                )
                free_delta, balance_delta = 0, -amount_fen
            else:
                raise InsufficientCreditsError(
                    "剩余搜题次数不足，请联系内测管理员增加次数"
                )
            connection.execute(
                """
                INSERT INTO usage_reservations(
                    id, user_id, source, amount_fen, status, created_at, updated_at
                ) VALUES (?, ?, ?, ?, 'reserved', ?, ?)
                """,
                (reservation_id, user_id, source, amount_fen, now, now),
            )
            connection.execute(
                """
                INSERT INTO account_ledger(
                    user_id, event_type, free_uses_delta, balance_fen_delta,
                    reference_id, created_at
                ) VALUES (?, 'solve_reserved', ?, ?, ?, ?)
                """,
                (user_id, free_delta, balance_delta, reservation_id, now),
            )
            connection.commit()
            return UsageReservation(reservation_id, user_id, source, amount_fen)
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()

    def commit_usage(self, reservation_id: str) -> None:
        self._finish_reservation(reservation_id, refund=False)

    def refund_usage(self, reservation_id: str) -> None:
        self._finish_reservation(reservation_id, refund=True)

    def _finish_reservation(self, reservation_id: str, *, refund: bool) -> None:
        now = int(time.time())
        connection = self._connect()
        try:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute(
                """
                SELECT user_id, source, amount_fen, status
                FROM usage_reservations WHERE id = ?
                """,
                (reservation_id,),
            ).fetchone()
            if row is None or row["status"] != "reserved":
                connection.rollback()
                return
            status = "refunded" if refund else "committed"
            connection.execute(
                "UPDATE usage_reservations SET status = ?, updated_at = ? WHERE id = ?",
                (status, now, reservation_id),
            )
            if refund:
                free_delta = 1 if row["source"] == "free" else 0
                balance_delta = row["amount_fen"] if row["source"] == "balance" else 0
                connection.execute(
                    """
                    UPDATE users
                    SET free_uses_remaining = free_uses_remaining + ?,
                        balance_fen = balance_fen + ?
                    WHERE id = ?
                    """,
                    (free_delta, balance_delta, row["user_id"]),
                )
                connection.execute(
                    """
                    INSERT INTO account_ledger(
                        user_id, event_type, free_uses_delta, balance_fen_delta,
                        reference_id, created_at
                    ) VALUES (?, 'solve_refunded', ?, ?, ?, ?)
                    """,
                    (
                        row["user_id"],
                        free_delta,
                        balance_delta,
                        reservation_id,
                        now,
                    ),
                )
            else:
                connection.execute(
                    """
                    INSERT INTO account_ledger(
                        user_id, event_type, reference_id, created_at
                    ) VALUES (?, 'solve_committed', ?, ?)
                    """,
                    (row["user_id"], reservation_id, now),
                )
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()

    def _create_session(self, user_id: str) -> Session:
        token = secrets.token_urlsafe(32)
        now = int(time.time())
        with self._connect() as connection:
            connection.execute(
                """
                INSERT INTO sessions(token_hash, user_id, expires_at, created_at)
                VALUES (?, ?, ?, ?)
                """,
                (self._token_hash(token), user_id, now + self._session_seconds, now),
            )
        return Session(token=token, account=self.authenticate(token))

    def _hash_password(self, password: str) -> str:
        salt = secrets.token_bytes(16)
        digest = hashlib.pbkdf2_hmac(
            "sha256", password.encode("utf-8"), salt, self._password_iterations
        )
        return f"pbkdf2_sha256${self._password_iterations}${salt.hex()}${digest.hex()}"

    def _verify_password(self, password: str, encoded: str) -> bool:
        try:
            algorithm, iterations, salt_hex, expected_hex = encoded.split("$", 3)
            if algorithm != "pbkdf2_sha256":
                return False
            actual = hashlib.pbkdf2_hmac(
                "sha256",
                password.encode("utf-8"),
                bytes.fromhex(salt_hex),
                int(iterations),
            )
            return hmac.compare_digest(actual, bytes.fromhex(expected_hex))
        except (ValueError, TypeError):
            return False

    @staticmethod
    def _token_hash(token: str) -> str:
        return hashlib.sha256(token.encode("utf-8")).hexdigest()

    @staticmethod
    def _account_from_row(row: sqlite3.Row) -> Account:
        return Account(
            id=row["id"],
            username=row["username"],
            free_uses_remaining=int(row["free_uses_remaining"]),
            balance_fen=int(row["balance_fen"]),
            status=row["status"] if "status" in row.keys() else "active",
        )

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self._database_path, timeout=10)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("PRAGMA journal_mode = WAL")
        connection.execute("PRAGMA busy_timeout = 10000")
        return connection
