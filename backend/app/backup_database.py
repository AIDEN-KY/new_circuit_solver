from __future__ import annotations

import argparse
import sqlite3
from datetime import datetime
from pathlib import Path

from .config import Settings


def backup_database(source: Path, destination_dir: Path, *, keep: int = 14) -> Path:
    source.parent.mkdir(parents=True, exist_ok=True)
    if not source.exists():
        sqlite3.connect(source).close()
    destination_dir.mkdir(parents=True, exist_ok=True)
    destination = destination_dir / f"circuit_solver_{datetime.now():%Y%m%d_%H%M%S}.db"
    with sqlite3.connect(source) as source_db, sqlite3.connect(destination) as target_db:
        source_db.backup(target_db)
        result = target_db.execute("PRAGMA integrity_check").fetchone()
        if result is None or result[0] != "ok":
            raise RuntimeError("数据库备份完整性检查失败")
    backups = sorted(destination_dir.glob("circuit_solver_*.db"), reverse=True)
    for expired in backups[max(1, keep):]:
        expired.unlink()
    return destination


def verify_database(path: Path) -> bool:
    with sqlite3.connect(path) as connection:
        row = connection.execute("PRAGMA integrity_check").fetchone()
    return row is not None and row[0] == "ok"


def main() -> None:
    parser = argparse.ArgumentParser(description="备份或检查 Circuit Solver SQLite 数据库")
    parser.add_argument("--verify", type=Path, help="只检查指定备份文件")
    parser.add_argument("--destination", type=Path, default=Path("backups"))
    parser.add_argument("--keep", type=int, default=14)
    args = parser.parse_args()
    if args.verify:
        if not verify_database(args.verify):
            raise SystemExit("备份文件校验失败")
        print("备份文件完整性正常")
        return
    path = backup_database(Settings.from_env().database_path, args.destination, keep=args.keep)
    print(f"数据库已备份：{path}")


if __name__ == "__main__":
    main()
