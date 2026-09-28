from __future__ import annotations

import sqlite3
import time
from pathlib import Path


class SolveRequestInProgress(ValueError):
    pass


class SolveRequestRepository:
    """保存客户端幂等编号，防止重试造成重复扣费和重复AI调用。"""

    def __init__(self, database_path: Path) -> None:
        self._database_path = database_path

    def initialize(self) -> None:
        with self._connect() as connection:
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS solve_requests (
                    user_id TEXT NOT NULL,
                    client_request_id TEXT NOT NULL,
                    status TEXT NOT NULL CHECK(status IN ('processing','completed','failed')),
                    response_json TEXT NOT NULL DEFAULT '',
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    PRIMARY KEY(user_id, client_request_id)
                )
                """
            )

    def completed_response(self, user_id: str, client_request_id: str) -> str | None:
        with self._connect() as connection:
            row = connection.execute(
                """SELECT status, response_json FROM solve_requests
                   WHERE user_id = ? AND client_request_id = ?""",
                (user_id, client_request_id),
            ).fetchone()
        if row is None or row["status"] == "failed":
            return None
        if row["status"] == "processing":
            raise SolveRequestInProgress("相同请求仍在处理中，请稍后查看")
        return str(row["response_json"])

    def start(self, user_id: str, client_request_id: str) -> None:
        now = int(time.time())
        with self._connect() as connection:
            connection.execute(
                """
                INSERT INTO solve_requests(user_id, client_request_id, status, created_at, updated_at)
                VALUES (?, ?, 'processing', ?, ?)
                ON CONFLICT(user_id, client_request_id) DO UPDATE SET
                    status = 'processing', response_json = '', updated_at = excluded.updated_at
                WHERE solve_requests.status = 'failed'
                """,
                (user_id, client_request_id, now, now),
            )

    def complete(self, user_id: str, client_request_id: str, response_json: str) -> None:
        with self._connect() as connection:
            connection.execute(
                """UPDATE solve_requests SET status='completed', response_json=?, updated_at=?
                   WHERE user_id=? AND client_request_id=?""",
                (response_json, int(time.time()), user_id, client_request_id),
            )

    def fail(self, user_id: str, client_request_id: str) -> None:
        with self._connect() as connection:
            connection.execute(
                """UPDATE solve_requests SET status='failed', updated_at=?
                   WHERE user_id=? AND client_request_id=?""",
                (int(time.time()), user_id, client_request_id),
            )

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self._database_path, timeout=10)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA journal_mode = WAL")
        connection.execute("PRAGMA busy_timeout = 10000")
        return connection
