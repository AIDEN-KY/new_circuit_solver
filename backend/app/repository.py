from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

from .image_processing import ImageProcessor
from .models import AskResponse, SimilarQuestion


@dataclass(frozen=True, slots=True)
class LibraryMatch:
    response: AskResponse
    similarity: float


ReviewStatus = Literal["pending_solution", "approved", "rejected"]


@dataclass(frozen=True, slots=True)
class QuestionRecord:
    question_id: str
    title: str
    review_status: ReviewStatus
    is_publishable: bool
    source_reference: str
    question_image_path: str
    answer_image_path: str
    response: AskResponse


class QuestionRepository:
    def __init__(self, database_path: Path) -> None:
        self._database_path = database_path

    def initialize(self) -> None:
        self._database_path.parent.mkdir(parents=True, exist_ok=True)
        with self._connect() as connection:
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS questions (
                    question_id TEXT PRIMARY KEY,
                    title TEXT NOT NULL,
                    image_hash TEXT NOT NULL,
                    response_json TEXT NOT NULL,
                    review_status TEXT NOT NULL DEFAULT 'approved',
                    is_publishable INTEGER NOT NULL DEFAULT 1,
                    source_reference TEXT NOT NULL DEFAULT '',
                    question_image_path TEXT NOT NULL DEFAULT '',
                    answer_image_path TEXT NOT NULL DEFAULT '',
                    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                )
                """
            )
            # 兼容第 28 批之前已经创建的 SQLite 数据库。
            existing_columns = {
                row["name"]
                for row in connection.execute("PRAGMA table_info(questions)").fetchall()
            }
            migrations = {
                "review_status": "TEXT NOT NULL DEFAULT 'approved'",
                "is_publishable": "INTEGER NOT NULL DEFAULT 1",
                "source_reference": "TEXT NOT NULL DEFAULT ''",
                "question_image_path": "TEXT NOT NULL DEFAULT ''",
                "answer_image_path": "TEXT NOT NULL DEFAULT ''",
            }
            for column, definition in migrations.items():
                if column not in existing_columns:
                    connection.execute(
                        f"ALTER TABLE questions ADD COLUMN {column} {definition}"
                    )
            connection.execute(
                "CREATE INDEX IF NOT EXISTS idx_questions_hash ON questions(image_hash)"
            )
            connection.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_questions_publishable
                ON questions(is_publishable, review_status)
                """
            )

    def upsert(
        self,
        question_id: str,
        title: str,
        fingerprint: int,
        response: AskResponse,
        *,
        review_status: ReviewStatus = "approved",
        is_publishable: bool = True,
        source_reference: str = "",
        question_image_path: str = "",
        answer_image_path: str = "",
    ) -> None:
        if review_status not in {"pending_solution", "approved", "rejected"}:
            raise ValueError(f"不支持的审核状态: {review_status}")
        if is_publishable and review_status != "approved":
            raise ValueError("只有审核通过的题目才能发布")
        payload = response.model_copy(update={"source": "library"}).model_dump_json()
        with self._connect() as connection:
            connection.execute(
                """
                INSERT INTO questions(
                    question_id, title, image_hash, response_json,
                    review_status, is_publishable, source_reference,
                    question_image_path, answer_image_path
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(question_id) DO UPDATE SET
                    title = excluded.title,
                    image_hash = excluded.image_hash,
                    response_json = excluded.response_json,
                    review_status = excluded.review_status,
                    is_publishable = excluded.is_publishable,
                    source_reference = excluded.source_reference,
                    question_image_path = excluded.question_image_path,
                    answer_image_path = excluded.answer_image_path
                """,
                (
                    question_id,
                    title,
                    f"{fingerprint:016x}",
                    payload,
                    review_status,
                    int(is_publishable),
                    source_reference,
                    question_image_path,
                    answer_image_path,
                ),
            )

    def search(
        self, fingerprint: int, threshold: float, limit: int = 4
    ) -> tuple[LibraryMatch | None, list[SimilarQuestion]]:
        scored: list[tuple[float, str, str, str]] = []
        with self._connect() as connection:
            rows = connection.execute(
                """
                SELECT question_id, title, image_hash, response_json
                FROM questions
                WHERE is_publishable = 1 AND review_status = 'approved'
                """
            ).fetchall()
        for row in rows:
            score = ImageProcessor.similarity(fingerprint, int(row["image_hash"], 16))
            scored.append((score, row["question_id"], row["title"], row["response_json"]))
        scored.sort(key=lambda item: item[0], reverse=True)

        similar = [
            SimilarQuestion(question_id=item[1], title=item[2], similarity=round(item[0], 4))
            for item in scored[:limit]
        ]
        if not scored or scored[0][0] < threshold:
            return None, similar
        response = AskResponse.model_validate(json.loads(scored[0][3]))
        return LibraryMatch(response=response, similarity=scored[0][0]), similar

    def get(self, question_id: str) -> QuestionRecord | None:
        """读取题库管理记录；待审核题只供管理和回归测试，不参与用户检索。"""
        with self._connect() as connection:
            row = connection.execute(
                """
                SELECT question_id, title, review_status, is_publishable,
                       source_reference, question_image_path, answer_image_path,
                       response_json
                FROM questions
                WHERE question_id = ?
                """,
                (question_id,),
            ).fetchone()
        if row is None:
            return None
        return QuestionRecord(
            question_id=row["question_id"],
            title=row["title"],
            review_status=row["review_status"],
            is_publishable=bool(row["is_publishable"]),
            source_reference=row["source_reference"],
            question_image_path=row["question_image_path"],
            answer_image_path=row["answer_image_path"],
            response=AskResponse.model_validate(json.loads(row["response_json"])),
        )

    def count_publishable(self) -> int:
        """返回当前可以被用户检索到的已审核题目数量。"""
        with self._connect() as connection:
            row = connection.execute(
                """
                SELECT COUNT(*) AS total
                FROM questions
                WHERE is_publishable = 1 AND review_status = 'approved'
                """
            ).fetchone()
        return int(row["total"] if row is not None else 0)

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self._database_path, timeout=10)
        connection.row_factory = sqlite3.Row
        return connection
