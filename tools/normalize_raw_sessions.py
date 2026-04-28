#!/usr/bin/env python3
"""Build analysis JSONL tables from MotorCursor raw session logs."""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path
from typing import Any


REQUIRED_FIELDS: dict[str, list[str]] = {
    "session_start": ["session_id", "participant_id"],
    "session_end": ["session_id"],
    "trial_start": ["trial_id", "session_id"],
    "trial_end": ["trial_id"],
    "event": ["event_type", "trial_id", "position"],
    "quality_event": ["event_type", "t_us"],
    "form_completed": ["session_id", "participant_id"],
}


def iter_raw_files(raw_path: Path) -> list[Path]:
    if raw_path.is_file():
        return [raw_path]
    return sorted(raw_path.glob("*_raw.jsonl"))


def read_jsonl(path: Path):
    with path.open("r", encoding="utf-8") as file:
        for line_number, line in enumerate(file, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError as exc:
                raise ValueError(f"{path}:{line_number}: invalid JSONL line") from exc


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as file:
        for row in rows:
            file.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")))
            file.write("\n")


def normalize(raw_files: list[Path], output_dir: Path, copy_raw: bool) -> None:
    participants: dict[str, dict[str, Any]] = {}
    sessions: dict[str, dict[str, Any]] = {}
    trials: dict[str, dict[str, Any]] = {}
    input_events: list[dict[str, Any]] = []
    block_events: list[dict[str, Any]] = []
    quality_events: list[dict[str, Any]] = []
    practice_events: list[dict[str, Any]] = []
    form_events: list[dict[str, Any]] = []
    validation_warnings = 0

    for raw_file in raw_files:
        for entry in read_jsonl(raw_file):
            kind = entry.get("kind")
            data = entry.get("data", {})
            if not isinstance(data, dict):
                continue

            # Basic schema validation
            required = REQUIRED_FIELDS.get(kind, [])
            missing = [f for f in required if f not in data]
            if missing:
                print(f"WARNING: {raw_file.name}: '{kind}' event missing fields: {missing}", file=sys.stderr)
                validation_warnings += 1

            if kind == "session_start":
                participant = data.get("participant_info")
                if isinstance(participant, dict):
                    participants[participant["participant_id"]] = participant

                session_id = data["session_id"]
                session = dict(data)
                session.pop("participant_info", None)
                session["raw_file"] = raw_file.name
                sessions[session_id] = session

            elif kind == "session_end":
                session_id = data.get("session_id")
                if session_id in sessions:
                    sessions[session_id].update(data)
                else:
                    sessions[str(session_id)] = dict(data)

            elif kind == "trial_start":
                trial_id = data["trial_id"]
                trials[trial_id] = dict(data)

            elif kind == "trial_end":
                trial_id = data["trial_id"]
                trial = trials.setdefault(trial_id, {})
                trial.update(data)

            elif kind == "event":
                input_events.append(dict(data))

            elif kind in {"block_start", "block_end"}:
                row = dict(data)
                row["kind"] = kind
                block_events.append(row)

            elif kind == "quality_event":
                quality_events.append(dict(data))

            elif kind in {"practice_start", "practice_end"}:
                row = dict(data)
                row["kind"] = kind
                practice_events.append(row)

            elif kind == "form_completed":
                row = dict(data)
                row["kind"] = kind
                form_events.append(row)

    output_dir.mkdir(parents=True, exist_ok=True)
    write_jsonl(output_dir / "participants.jsonl", sorted(participants.values(), key=lambda row: row["participant_id"]))
    write_jsonl(output_dir / "sessions.jsonl", sorted(sessions.values(), key=lambda row: row.get("session_id", "")))
    write_jsonl(output_dir / "trials.jsonl", sorted(trials.values(), key=lambda row: row.get("trial_id", "")))
    write_jsonl(output_dir / "input_events.jsonl", input_events)
    write_jsonl(output_dir / "block_events.jsonl", block_events)
    write_jsonl(output_dir / "quality_events.jsonl", quality_events)
    write_jsonl(output_dir / "practice_events.jsonl", practice_events)
    write_jsonl(output_dir / "form_events.jsonl", form_events)

    if validation_warnings > 0:
        print(f"Completed with {validation_warnings} validation warning(s).", file=sys.stderr)

    if copy_raw:
        raw_output_dir = output_dir / "raw_sessions"
        raw_output_dir.mkdir(exist_ok=True)
        for raw_file in raw_files:
            shutil.copy2(raw_file, raw_output_dir / raw_file.name)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("raw_path", type=Path, help="A *_raw.jsonl file or a directory with raw session logs.")
    parser.add_argument("-o", "--output-dir", type=Path, default=Path("dataset"), help="Output dataset directory.")
    parser.add_argument("--no-copy-raw", action="store_true", help="Do not copy raw logs into output/raw_sessions.")
    args = parser.parse_args()

    raw_files = iter_raw_files(args.raw_path)
    if not raw_files:
        raise SystemExit(f"No *_raw.jsonl files found in {args.raw_path}")

    normalize(raw_files, args.output_dir, copy_raw=not args.no_copy_raw)
    print(f"Normalized {len(raw_files)} raw session file(s) into {args.output_dir}")


if __name__ == "__main__":
    main()
