"""Eval runner for the AIMANA harness.

Runs Claude Code in headless mode against each golden task, captures the diff,
runs acceptance commands, and scores against the rubric.

Usage:
    python evals/run.py                    # Run all tasks
    python evals/run.py --task <name>      # Run one task
    python evals/run.py --only-failing     # Re-run failed tasks from last run
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import time
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).parent.parent.resolve()
TASKS_DIR = ROOT / "evals" / "tasks"
RUNS_DIR = ROOT / "evals" / "runs"
RUBRIC_PATH = ROOT / "evals" / "rubric.md"

CLAUDE_BIN = shutil.which("claude") or "claude"
CLAUDE_TIMEOUT_SEC = 600


@dataclass
class TaskSpec:
    name: str
    setup: list[str]
    prompt: str
    acceptance: list[str]
    rubric_overrides: list[str] = field(default_factory=list)


@dataclass
class TaskResult:
    name: str
    started_at: str
    duration_sec: float
    setup_ok: bool
    claude_exit_code: int | None
    diff_lines: int
    acceptance: list[tuple[str, bool]]
    rubric: list[tuple[str, str]]  # (item, "pass"|"fail"|"manual")
    score: str  # e.g. "8/10"


def parse_task(path: Path) -> TaskSpec:
    text = path.read_text()
    sections = _split_h2(text)
    return TaskSpec(
        name=path.stem,
        setup=_lines_starting_with(sections.get("Setup", ""), "- "),
        prompt=sections.get("Prompt", "").strip(),
        acceptance=_lines_starting_with(sections.get("Acceptance", ""), "- "),
        rubric_overrides=_lines_starting_with(
            sections.get("Rubric overrides", ""), "- "
        ),
    )


def _split_h2(text: str) -> dict[str, str]:
    pattern = re.compile(r"^##\s+(.+)$", re.MULTILINE)
    parts = pattern.split(text)
    sections: dict[str, str] = {}
    # parts: [pre, h2_1, body_1, h2_2, body_2, ...]
    for i in range(1, len(parts), 2):
        sections[parts[i].strip()] = parts[i + 1] if i + 1 < len(parts) else ""
    return sections


def _lines_starting_with(block: str, prefix: str) -> list[str]:
    return [
        line[len(prefix) :].strip()
        for line in block.splitlines()
        if line.strip().startswith(prefix)
    ]


def run_task(task: TaskSpec) -> TaskResult:
    started = datetime.now(timezone.utc).isoformat()
    t0 = time.perf_counter()

    setup_ok = _run_all(task.setup, label=f"[{task.name}] setup")

    claude_exit: int | None = None
    if setup_ok:
        claude_exit = _run_claude_headless(task.prompt)

    diff_lines = _diff_lines()
    acceptance = [(cmd, _run_one(cmd)) for cmd in task.acceptance]

    rubric = _score_rubric(task)
    passes = sum(1 for _, v in rubric if v == "pass")
    total = len(rubric)
    score = f"{passes}/{total}"

    return TaskResult(
        name=task.name,
        started_at=started,
        duration_sec=time.perf_counter() - t0,
        setup_ok=setup_ok,
        claude_exit_code=claude_exit,
        diff_lines=diff_lines,
        acceptance=acceptance,
        rubric=rubric,
        score=score,
    )


def _run_all(cmds: list[str], label: str = "") -> bool:
    for cmd in cmds:
        if not _run_one(cmd, label=label):
            return False
    return True


def _run_one(cmd: str, label: str = "") -> bool:
    proc = subprocess.run(  # noqa: S602
        cmd, shell=True, cwd=ROOT, capture_output=True, text=True
    )
    if proc.returncode != 0:
        sys.stderr.write(f"{label} FAILED: {cmd}\n{proc.stderr}\n")
    return proc.returncode == 0


def _run_claude_headless(prompt: str) -> int | None:
    """Run Claude Code in headless mode. Returns exit code."""
    try:
        proc = subprocess.run(
            [CLAUDE_BIN, "-p", prompt, "--dangerously-skip-permissions"],
            cwd=ROOT,
            timeout=CLAUDE_TIMEOUT_SEC,
            capture_output=True,
            text=True,
        )
        return proc.returncode
    except subprocess.TimeoutExpired:
        return -1
    except FileNotFoundError:
        sys.stderr.write(f"claude binary not found at {CLAUDE_BIN}\n")
        return None


def _diff_lines() -> int:
    proc = subprocess.run(
        ["git", "diff", "--stat", "HEAD"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        return 0
    match = re.search(r"(\d+) insertion", proc.stdout)
    return int(match.group(1)) if match else 0


def _score_rubric(task: TaskSpec) -> list[tuple[str, str]]:
    """Lightweight automated rubric scoring.

    Items the runner can check automatically are scored pass/fail.
    Items that require human judgment are marked "manual".
    """
    results: list[tuple[str, str]] = []

    # 1. Tests written before implementation (check git log)
    log = subprocess.run(
        ["git", "log", "--name-only", "--pretty=format:--commit--"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    ).stdout
    test_first = _tests_came_first(log)
    results.append(("tests-before-impl", "pass" if test_first else "fail"))

    # 7-9. Verification gates
    for label, cmd in (
        ("pytest", "pytest -q"),
        ("ruff", "ruff check ."),
        ("mypy", "mypy --strict app/"),
    ):
        results.append((label, "pass" if _run_one(cmd) else "fail"))

    # Items that require judgment
    for item in (
        "no-over-engineering",
        "stayed-in-scope",
        "no-hook-bypass",
        "architecture-respected",
        "pydantic-at-boundaries",
        "coverage-rule",
    ):
        results.append((item, "manual"))

    for override in task.rubric_overrides:
        results.append((f"override::{override[:60]}", "manual"))

    return results


def _tests_came_first(log: str) -> bool:
    """First commit on branch should touch test files before non-test ones."""
    commits = log.split("--commit--")
    for commit in commits:
        files = [f for f in commit.strip().splitlines() if f]
        if not files:
            continue
        return any(_is_test(f) for f in files) and not all(
            _is_source(f) and not _is_test(f) for f in files
        )
    return False


def _is_test(path: str) -> bool:
    return path.startswith("tests/") or "/test_" in path or path.endswith("_test.py")


def _is_source(path: str) -> bool:
    return path.endswith(".py")


def _failed_from_last_report() -> set[str] | None:
    """Read the most recent report and return names of tasks that failed acceptance."""
    reports = sorted(RUNS_DIR.glob("*.json"))
    if not reports:
        return None
    data = json.loads(reports[-1].read_text())
    return {
        r["name"]
        for r in data.get("results", [])
        if not all(ok for _, ok in r.get("acceptance", []))
    }


def write_report(results: list[TaskResult]) -> Path:
    RUNS_DIR.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    path = RUNS_DIR / f"{ts}.json"
    path.write_text(
        json.dumps(
            {
                "timestamp": ts,
                "results": [asdict(r) for r in results],
            },
            indent=2,
        )
    )
    return path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--task", help="Run a single task by name (file stem)")
    parser.add_argument(
        "--only-failing",
        action="store_true",
        help="Re-run only tasks that failed in the most recent report",
    )
    args = parser.parse_args()

    task_files = sorted(TASKS_DIR.glob("*.md"))
    if args.task:
        task_files = [p for p in task_files if p.stem == args.task]
        if not task_files:
            sys.stderr.write(f"No task named {args.task!r} in {TASKS_DIR}\n")
            return 1
    elif args.only_failing:
        failed_names = _failed_from_last_report()
        if failed_names is None:
            sys.stderr.write("No previous report found in evals/runs/\n")
            return 1
        task_files = [p for p in task_files if p.stem in failed_names]
        if not task_files:
            print("No failing tasks in last report. All green.")
            return 0

    results = [run_task(parse_task(p)) for p in task_files]
    report_path = write_report(results)

    print(f"\nReport: {report_path}")
    for r in results:
        print(f"  {r.name}: score={r.score}, claude_exit={r.claude_exit_code}")

    failed = [r for r in results if not all(ok for _, ok in r.acceptance)]
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
