from __future__ import annotations

import argparse
import json
from pathlib import Path

from .config import Settings
from .image_processing import ImageProcessor
from .models import AskResponse
from .repository import QuestionRepository


def main() -> None:
    parser = argparse.ArgumentParser(description="向 Circuit Solver 本地题库导入题目")
    parser.add_argument("--id", required=True, help="题目唯一编号，例如 q_1001")
    parser.add_argument("--title", required=True, help="题目标题")
    parser.add_argument("--image", required=True, type=Path, help="题目区域图片")
    parser.add_argument("--response", required=True, type=Path, help="AskResponse JSON 文件")
    parser.add_argument(
        "--review-status",
        choices=("pending_solution", "approved", "rejected"),
        default="approved",
        help="审核状态；缺少可靠解题过程时使用 pending_solution",
    )
    parser.add_argument(
        "--publishable",
        action="store_true",
        help="允许被用户检索；只有 approved 题目可以开启",
    )
    parser.add_argument("--source-reference", default="", help="教材或答案来源说明")
    parser.add_argument("--answer-image", type=Path, help="标准答案图片，仅供审核")
    args = parser.parse_args()

    settings = Settings.from_env()
    image_bytes = args.image.read_bytes()
    response = AskResponse.model_validate(json.loads(args.response.read_text("utf-8")))
    repository = QuestionRepository(settings.database_path)
    repository.initialize()
    repository.upsert(
        question_id=args.id,
        title=args.title,
        fingerprint=ImageProcessor.fingerprint(image_bytes),
        response=response,
        review_status=args.review_status,
        is_publishable=args.publishable,
        source_reference=args.source_reference,
        question_image_path=str(args.image),
        answer_image_path=str(args.answer_image) if args.answer_image else "",
    )
    state = "可发布" if args.publishable else "仅供审核/回归测试"
    print(f"已导入题目 {args.id}: {args.title}（{args.review_status}，{state}）")


if __name__ == "__main__":
    main()
