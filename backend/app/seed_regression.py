from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

from .config import BACKEND_DIR, Settings
from .image_processing import ImageProcessor
from .models import AskResponse
from .repository import QuestionRepository


@dataclass(frozen=True, slots=True)
class RegressionSeed:
    question_id: str
    title: str
    directory: str
    source_reference: str


SEEDS = (
    RegressionSeed(
        "q_1_9_8",
        "理想电压源除去后的端电压",
        "q_1_9_8",
        "用户提供的教材习题1.9.8及答案页",
    ),
    RegressionSeed(
        "q_1_6_12",
        "梯形电阻网络等效电阻与支路电流",
        "q_1_6_12",
        "用户提供的教材习题1.6.12及答案页",
    ),
    RegressionSeed(
        "q_10_2_12",
        "晶体管双输出放大电路",
        "q_10_2_12",
        "用户提供的教材习题10.2.12及答案页",
    ),
)


def seed_regression_questions(repository: QuestionRepository | None = None) -> int:
    resolved_repository = repository or QuestionRepository(
        Settings.from_env().database_path
    )
    resolved_repository.initialize()
    regression_dir = BACKEND_DIR / "data" / "regression"
    for seed in SEEDS:
        directory = regression_dir / seed.directory
        question_path = directory / "question.jpg"
        answer_path = directory / "answer.jpg"
        response_path = directory / "response.json"
        response = AskResponse.model_validate(
            json.loads(response_path.read_text(encoding="utf-8"))
        )
        resolved_repository.upsert(
            question_id=seed.question_id,
            title=seed.title,
            fingerprint=ImageProcessor.fingerprint(question_path.read_bytes()),
            response=response,
            review_status="pending_solution",
            is_publishable=False,
            source_reference=seed.source_reference,
            question_image_path=str(question_path.relative_to(BACKEND_DIR)),
            answer_image_path=str(answer_path.relative_to(BACKEND_DIR)),
        )
    return len(SEEDS)


def main() -> None:
    count = seed_regression_questions()
    print(f"已写入 {count} 道待审核回归题；这些记录不会向用户发布。")


if __name__ == "__main__":
    main()
