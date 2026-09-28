from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import statistics
import time
from datetime import datetime
from pathlib import Path

from .ai_solver import AiSolver
from .config import BACKEND_DIR, Settings
from .models import AiSolution
from .providers import create_ai_provider


EVAL_DIR = BACKEND_DIR / "evals"


def _load_local_env() -> None:
    """命令行评测与 uvicorn --env-file 保持一致，不输出任何密钥。"""
    path = BACKEND_DIR / ".env"
    if not path.is_file():
        return
    for raw_line in path.read_text(encoding="utf-8-sig").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        name, value = line.split("=", 1)
        os.environ.setdefault(name.strip(), value.strip())


def _load_cases(path: Path) -> list[dict]:
    cases = json.loads(path.read_text(encoding="utf-8"))
    for case in cases:
        image = (path.parent / case["image"]).resolve()
        if not image.is_file():
            raise FileNotFoundError(f"评测图片不存在：{image}")
        case["resolved_image"] = image
    return cases


def _extract_value(text: str, pattern: str) -> float | None:
    match = re.search(pattern, text.replace("\\", ""), re.IGNORECASE | re.MULTILINE)
    return float(match.group(1)) if match else None


def _score(case: dict, solution: AiSolution, elapsed: float) -> dict:
    text = solution.final_answer + " " + solution.final_answer_latex
    target_results = []
    for target in case["targets"]:
        actual = _extract_value(text, target["pattern"])
        passed = actual is not None and abs(actual - target["expected"]) <= target["tolerance"]
        target_results.append({**target, "actual": actual, "passed": passed})
    expected_units = {item["unit"] for item in case["targets"] if item["unit"]}
    unit_text = solution.unit_check.actual_unit + " " + text
    units_passed = solution.unit_check.passed and all(unit in unit_text for unit in expected_units)
    return {
        "id": case["id"], "structured": True,
        "answer_passed": all(item["passed"] for item in target_results),
        "units_passed": units_passed, "confidence": solution.confidence,
        "elapsed_seconds": round(elapsed, 3), "targets": target_results,
        "final_answer": solution.final_answer,
        "final_answer_latex": solution.final_answer_latex,
        "error": None,
    }


async def _run(cases: list[dict], live: bool) -> list[dict]:
    solver = AiSolver(create_ai_provider(Settings.from_env())) if live else None
    results = []
    for case in cases:
        started = time.perf_counter()
        try:
            if live:
                solution = await solver.solve(case["resolved_image"].read_bytes())
            else:
                response_path = case["resolved_image"].with_name("response.json")
                payload = json.loads(response_path.read_text(encoding="utf-8"))
                solution = AiSolution.model_validate(
                    {name: payload[name] for name in AiSolution.model_fields}
                )
            results.append(_score(case, solution, time.perf_counter() - started))
        except Exception as error:
            results.append({"id": case["id"], "structured": False, "answer_passed": False, "units_passed": False, "confidence": "", "elapsed_seconds": round(time.perf_counter() - started, 3), "targets": [], "error": str(error)})
    return results


def _summary(results: list[dict], live: bool) -> dict:
    count = len(results)
    elapsed = sorted(item["elapsed_seconds"] for item in results)
    p95_index = max(0, min(count - 1, int(count * 0.95 + 0.999) - 1))
    return {
        "mode": "live" if live else "offline", "case_count": count,
        "structured_success_rate": sum(item["structured"] for item in results) / count,
        "answer_accuracy": sum(item["answer_passed"] for item in results) / count,
        "unit_accuracy": sum(item["units_passed"] for item in results) / count,
        "mean_elapsed_seconds": round(statistics.mean(elapsed), 3),
        "p95_elapsed_seconds": elapsed[p95_index],
        "confidence_counts": {level: sum(item["confidence"] == level for item in results) for level in ("high", "medium", "low")},
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Circuit Solver AI 回归评测（默认离线，不产生API费用）")
    parser.add_argument("--live", action="store_true", help="真实调用当前 AI Provider，会产生费用")
    parser.add_argument("--cases", type=Path, default=EVAL_DIR / "cases.json")
    parser.add_argument("--case", action="append", dest="case_ids", help="只运行指定案例ID，可重复填写")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    _load_local_env()
    cases = _load_cases(args.cases.resolve())
    if args.case_ids:
        selected = set(args.case_ids)
        cases = [case for case in cases if case["id"] in selected]
        if not cases:
            raise SystemExit("未找到指定评测案例")
    results = asyncio.run(_run(cases, args.live))
    report = {"generated_at": datetime.now().isoformat(timespec="seconds"), "summary": _summary(results, args.live), "results": results}
    output = args.output or (EVAL_DIR / "reports" / f"{datetime.now():%Y%m%d_%H%M%S}_{'live' if args.live else 'offline'}.json")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report["summary"], ensure_ascii=False, indent=2))
    print(f"完整报告：{output}")


if __name__ == "__main__":
    main()
