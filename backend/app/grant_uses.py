from __future__ import annotations

import argparse
from pathlib import Path

from .account_repository import (
    AccountNotFoundError,
    AccountRepository,
    DuplicateGrantError,
)
from .config import BACKEND_DIR


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("次数必须大于0")
    return parsed


def main() -> None:
    parser = argparse.ArgumentParser(description="为指定用户人工发放搜题次数")
    parser.add_argument("--user-id", required=True, help="App账号页显示的用户ID")
    parser.add_argument("--uses", required=True, type=positive_int, help="增加次数")
    parser.add_argument("--operator", required=True, help="管理员标识")
    parser.add_argument(
        "--reference",
        required=True,
        help="唯一业务流水号，例如日期加转账单号；重复值不会二次到账",
    )
    parser.add_argument("--note", default="", help="可选备注，不要记录敏感支付信息")
    parser.add_argument(
        "--database",
        type=Path,
        default=BACKEND_DIR / "data" / "circuit_solver.db",
        help="SQLite数据库路径",
    )
    args = parser.parse_args()

    repository = AccountRepository(
        args.database,
        initial_free_uses=3,
        solve_price_fen=10,
        session_days=30,
    )
    repository.initialize()
    try:
        account = repository.grant_uses(
            args.user_id,
            args.uses,
            operator=args.operator,
            reference_id=args.reference,
            note=args.note,
        )
    except (AccountNotFoundError, DuplicateGrantError, ValueError) as error:
        parser.error(str(error))
    print(
        f"发放成功：用户 {account.username}（{account.id}），"
        f"当前剩余 {account.free_uses_remaining} 次"
    )


if __name__ == "__main__":
    main()
