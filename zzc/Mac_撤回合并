#!/usr/bin/env python3
from __future__ import annotations

import shutil
import sys
from pathlib import Path

sys.dont_write_bytecode = True


SCRIPT_PATH = Path(sys.executable if getattr(sys, "frozen", False) else __file__).resolve()
START_DIR = SCRIPT_PATH.parent
ZZC_DIR = START_DIR if START_DIR.name == "zzc" else START_DIR / "zzc"
if not ZZC_DIR.exists() and (START_DIR.parent / "zzc").exists():
    ZZC_DIR = START_DIR.parent / "zzc"
ROLLBACK_DIR = ZZC_DIR / "撤回合并"


def read_manifest(path: Path) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    manifest = path / "manifest.txt"
    if not manifest.exists():
        return out
    for line in manifest.read_text(encoding="utf-8-sig").splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        out.setdefault(key.strip(), []).append(value.strip())
    return out


def latest_logs() -> list[Path]:
    if not ROLLBACK_DIR.exists():
        return []
    logs = [p for p in ROLLBACK_DIR.iterdir() if p.is_dir() and p.name.lower() != "logs"]
    return sorted(logs, key=lambda p: p.name, reverse=True)[:3]


def first(meta: dict[str, list[str]], key: str, default: str = "") -> str:
    values = meta.get(key) or []
    return values[0] if values else default


def choose_log(logs: list[Path]) -> Path | None:
    print("choose rollback backup:")
    for idx, log in enumerate(logs, 1):
        meta = read_manifest(log)
        created = first(meta, "created_at", log.name)
        ops_count = first(meta, "ops_count", "?")
        keep_count = first(meta, "keep_count", "?")
        print(f"{idx}. {log.name}  {created}  ops={ops_count} keep={keep_count}")
    print("0. cancel")
    choice = input("number: ").strip()
    if choice in {"", "0"} or not choice.isdigit():
        return None
    index = int(choice)
    if index < 1 or index > len(logs):
        return None
    return logs[index - 1]


def restore_state_files(log: Path, meta: dict[str, list[str]]) -> None:
    for item in meta.get("state_path", []):
        target_text, _, backup_text = item.partition("|")
        if not target_text or not backup_text:
            continue
        target = Path(target_text)
        backup = log / backup_text
        if backup.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(backup, target)
            print(f"restored state: {target}")
        else:
            print(f"missing state backup: {backup}")


def restore_log(log: Path) -> None:
    meta = read_manifest(log)
    ops_path = Path(first(meta, "ops_path"))
    target_paths = [Path(item) for item in first(meta, "target_paths").split("|") if item]
    if not ops_path:
        raise RuntimeError("manifest missing ops_path")

    before_zzc = log / "before_zzc.dict.yaml"
    if before_zzc.exists():
        shutil.copy2(before_zzc, ops_path)
        print(f"restored zzc: {ops_path}")
    else:
        print("missing before_zzc.dict.yaml; skipped zzc restore")

    dict_dir = log / "dicts"
    for target in target_paths:
        backup = dict_dir / target.name
        if backup.exists():
            shutil.copy2(backup, target)
            print(f"restored dict: {target}")
        else:
            print(f"missing dict backup: {target}")

    restore_state_files(log, meta)


def main() -> int:
    logs = latest_logs()
    if not logs:
        print("no rollback backup")
        return 0
    log = choose_log(logs)
    if not log:
        print("cancelled")
        return 0
    print(f"will restore: {log.name}")
    confirm = input("this overwrites dict and zzc state files. type YES: ").strip()
    if confirm != "YES":
        print("cancelled")
        return 0
    restore_log(log)
    print("rollback done")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"rollback failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
