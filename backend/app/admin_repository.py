from __future__ import annotations

import hashlib
import hmac
import secrets
import sqlite3
import time
from dataclasses import dataclass
from pathlib import Path


class AdminDisabledError(ValueError):
    pass


class InvalidAdminCredentialsError(ValueError):
    pass


class InvalidAdminSessionError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class AdminSession:
    token: str
    username: str


class AdminRepository:
    """后台账号和会话；后台密钥只从环境变量读取，不写入 Flutter。"""

    _password_iterations = 310_000

    def __init__(self, database_path: Path, *, username: str, password: str, session_days: int) -> None:
        self._database_path = database_path
        self._username = username.strip()
        self._password = password
        self._session_seconds = session_days * 24 * 60 * 60

    @property
    def enabled(self) -> bool:
        return bool(self._username and self._password)

    def initialize(self) -> None:
        with self._connect() as connection:
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS admin_users (
                    username TEXT PRIMARY KEY COLLATE NOCASE,
                    password_hash TEXT NOT NULL,
                    disabled INTEGER NOT NULL DEFAULT 0,
                    created_at INTEGER NOT NULL
                );
                CREATE TABLE IF NOT EXISTS admin_sessions (
                    token_hash TEXT PRIMARY KEY,
                    username TEXT NOT NULL REFERENCES admin_users(username) ON DELETE CASCADE,
                    expires_at INTEGER NOT NULL,
                    created_at INTEGER NOT NULL
                );
                """
            )
            if self.enabled:
                row = connection.execute(
                    "SELECT username FROM admin_users WHERE username = ?",
                    (self._username,),
                ).fetchone()
                if row is None:
                    connection.execute(
                        "INSERT INTO admin_users(username, password_hash, created_at) VALUES (?, ?, ?)",
                        (self._username, self._hash_password(self._password), int(time.time())),
                    )

    def login(self, username: str, password: str) -> AdminSession:
        if not self.enabled:
            raise AdminDisabledError("后台尚未配置管理员账号")
        with self._connect() as connection:
            row = connection.execute(
                "SELECT username, password_hash, disabled FROM admin_users WHERE username = ? COLLATE NOCASE",
                (username.strip(),),
            ).fetchone()
        if row is None or row["disabled"] or not self._verify_password(password, row["password_hash"]):
            raise InvalidAdminCredentialsError("管理员账号或密码错误")
        token = secrets.token_urlsafe(32)
        now = int(time.time())
        with self._connect() as connection:
            connection.execute(
                "INSERT INTO admin_sessions(token_hash, username, expires_at, created_at) VALUES (?, ?, ?, ?)",
                (self._token_hash(token), row["username"], now + self._session_seconds, now),
            )
        return AdminSession(token, row["username"])

    def authenticate(self, token: str) -> str:
        with self._connect() as connection:
            row = connection.execute(
                """SELECT s.username, u.disabled FROM admin_sessions s
                   JOIN admin_users u ON u.username = s.username
                   WHERE s.token_hash = ? AND s.expires_at > ?""",
                (self._token_hash(token), int(time.time())),
            ).fetchone()
        if row is None or row["disabled"]:
            raise InvalidAdminSessionError("后台登录已失效")
        return str(row["username"])

    def logout(self, token: str) -> None:
        with self._connect() as connection:
            connection.execute("DELETE FROM admin_sessions WHERE token_hash = ?", (self._token_hash(token),))

    @staticmethod
    def _token_hash(token: str) -> str:
        return hashlib.sha256(token.encode("utf-8")).hexdigest()

    def _hash_password(self, password: str) -> str:
        salt = secrets.token_bytes(16)
        digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, self._password_iterations)
        return f"pbkdf2_sha256${self._password_iterations}${salt.hex()}${digest.hex()}"

    def _verify_password(self, password: str, encoded: str) -> bool:
        try:
            algorithm, iterations, salt, expected = encoded.split("$", 3)
            actual = hashlib.pbkdf2_hmac("sha256", password.encode(), bytes.fromhex(salt), int(iterations))
            return algorithm == "pbkdf2_sha256" and hmac.compare_digest(actual, bytes.fromhex(expected))
        except (ValueError, TypeError):
            return False

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self._database_path, timeout=10)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("PRAGMA journal_mode = WAL")
        connection.execute("PRAGMA busy_timeout = 10000")
        return connection
