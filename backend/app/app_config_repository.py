from __future__ import annotations

import json
import sqlite3
import time
from dataclasses import asdict, dataclass
from pathlib import Path


@dataclass(frozen=True, slots=True)
class AppConfig:
    announcement_enabled: bool = False
    announcement_title: str = ""
    announcement_message: str = ""
    maintenance_mode: bool = False
    maintenance_message: str = "系统维护中，请稍后再试。"
    support_message: str = "次数不足时，请联系内测管理员。"
    qq_group: str = ""
    initial_free_uses: int = 3
    min_supported_version: str = "1.7.0"
    latest_version: str = "1.7.0"
    download_url: str = ""
    revision: int = 1
    updated_at: int = 0


class AppConfigRepository:
    """保存可在线修改的非敏感客户端配置和管理员审计记录。"""

    def __init__(self, database_path: Path, *, default_initial_free_uses: int) -> None:
        self._database_path = database_path
        self._default_initial_free_uses = default_initial_free_uses

    def initialize(self) -> None:
        self._database_path.parent.mkdir(parents=True, exist_ok=True)
        with self._connect() as connection:
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS app_config (
                    singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
                    announcement_enabled INTEGER NOT NULL DEFAULT 0,
                    announcement_title TEXT NOT NULL DEFAULT '',
                    announcement_message TEXT NOT NULL DEFAULT '',
                    maintenance_mode INTEGER NOT NULL DEFAULT 0,
                    maintenance_message TEXT NOT NULL DEFAULT '系统维护中，请稍后再试。',
                    support_message TEXT NOT NULL DEFAULT '次数不足时，请联系内测管理员。',
                    qq_group TEXT NOT NULL DEFAULT '',
                    initial_free_uses INTEGER NOT NULL DEFAULT 3,
                    min_supported_version TEXT NOT NULL DEFAULT '1.7.0',
                    latest_version TEXT NOT NULL DEFAULT '1.7.0',
                    download_url TEXT NOT NULL DEFAULT '',
                    revision INTEGER NOT NULL DEFAULT 1,
                    updated_at INTEGER NOT NULL
                );
                CREATE TABLE IF NOT EXISTS admin_audit_log (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    operator TEXT NOT NULL,
                    action TEXT NOT NULL,
                    target TEXT NOT NULL,
                    before_json TEXT NOT NULL DEFAULT '{}',
                    after_json TEXT NOT NULL DEFAULT '{}',
                    created_at INTEGER NOT NULL
                );
                """
            )
            connection.execute(
                """
                INSERT OR IGNORE INTO app_config(
                    singleton, initial_free_uses, updated_at
                ) VALUES (1, ?, ?)
                """,
                (self._default_initial_free_uses, int(time.time())),
            )

    def get(self) -> AppConfig:
        with self._connect() as connection:
            row = connection.execute("SELECT * FROM app_config WHERE singleton = 1").fetchone()
        if row is None:
            raise RuntimeError("应用配置尚未初始化")
        return self._from_row(row)

    def update(self, value: AppConfig, *, operator: str) -> AppConfig:
        before = self.get()
        now = int(time.time())
        updated = AppConfig(
            **{
                **asdict(value),
                "revision": before.revision + 1,
                "updated_at": now,
            }
        )
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            connection.execute(
                """
                UPDATE app_config SET
                    announcement_enabled = ?, announcement_title = ?,
                    announcement_message = ?, maintenance_mode = ?,
                    maintenance_message = ?, support_message = ?, qq_group = ?,
                    initial_free_uses = ?, min_supported_version = ?,
                    latest_version = ?, download_url = ?, revision = ?, updated_at = ?
                WHERE singleton = 1
                """,
                (
                    int(updated.announcement_enabled), updated.announcement_title,
                    updated.announcement_message, int(updated.maintenance_mode),
                    updated.maintenance_message, updated.support_message,
                    updated.qq_group, updated.initial_free_uses,
                    updated.min_supported_version, updated.latest_version,
                    updated.download_url, updated.revision, updated.updated_at,
                ),
            )
            self._insert_audit(
                connection, operator, "update_app_config", "app_config",
                asdict(before), asdict(updated), now,
            )
            connection.commit()
        return updated

    def record_audit(
        self,
        *,
        operator: str,
        action: str,
        target: str,
        before: dict[str, object],
        after: dict[str, object],
    ) -> None:
        with self._connect() as connection:
            self._insert_audit(
                connection, operator, action, target, before, after, int(time.time())
            )

    @staticmethod
    def _insert_audit(
        connection: sqlite3.Connection,
        operator: str,
        action: str,
        target: str,
        before: dict[str, object],
        after: dict[str, object],
        created_at: int,
    ) -> None:
        connection.execute(
            """
            INSERT INTO admin_audit_log(
                operator, action, target, before_json, after_json, created_at
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                operator, action, target,
                json.dumps(before, ensure_ascii=False, sort_keys=True),
                json.dumps(after, ensure_ascii=False, sort_keys=True),
                created_at,
            ),
        )

    @staticmethod
    def _from_row(row: sqlite3.Row) -> AppConfig:
        return AppConfig(
            announcement_enabled=bool(row["announcement_enabled"]),
            announcement_title=row["announcement_title"],
            announcement_message=row["announcement_message"],
            maintenance_mode=bool(row["maintenance_mode"]),
            maintenance_message=row["maintenance_message"],
            support_message=row["support_message"],
            qq_group=row["qq_group"],
            initial_free_uses=int(row["initial_free_uses"]),
            min_supported_version=row["min_supported_version"],
            latest_version=row["latest_version"],
            download_url=row["download_url"],
            revision=int(row["revision"]),
            updated_at=int(row["updated_at"]),
        )

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self._database_path, timeout=10)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA journal_mode = WAL")
        connection.execute("PRAGMA busy_timeout = 10000")
        return connection
