#!/usr/bin/env python3
from __future__ import annotations

import shutil
import sys
from pathlib import Path

sys.dont_write_bytecode = True


ROOT = Path(__file__).resolve().parents[1]
ZZC_DIR = ROOT / "zzc"
ROLLBACK_LOGS = ZZC_DIR / "撤回合并" / "logs"


def read_manifest(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    manifest = path / "manifest.txt"
    if not manifest.exists():
        return out
    for line in manifest.read_text(encoding="utf-8-sig").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            out[key.strip()] = value.strip()
    return out


def latest_logs() -> list[Path]:
    if not ROLLBACK_LOGS.exists():
        return []
    return sorted([p for p in ROLLBACK_LOGS.iterdir() if p.is_dir()], key=lambda p: p.name, reverse=True)[:3]


def choose_log(logs: list[Path]) -> Path | None:
    print("请选择要恢复的备份：")
    for idx, log in enumerate(logs, 1):
        meta = read_manifest(log)
        created = meta.get("created_at", log.name)
        ops_count = meta.get("ops_count", "?")
        keep_count = meta.get("keep_count", "?")
        print(f"{idx}. {log.name}  {created}  操作 {ops_count} 条，写入 {keep_count} 条")
    print("0. 取消")
    choice = input("输入序号：").strip()
    if choice == "0" or choice == "":
        return None
    if not choice.isdigit():
        return None
    index = int(choice)
    if index < 1 or index > len(logs):
        return None
    return logs[index - 1]


def restore_log(log: Path) -> None:
    meta = read_manifest(log)
    ops_path = Path(meta.get("ops_path", ""))
    target_paths = [Path(item) for item in meta.get("target_paths", "").split("|") if item]
    if not ops_path:
        raise RuntimeError("manifest 缺少 ops_path")

    before_zzc = log / "before_zzc.dict.yaml"
    if before_zzc.exists():
        shutil.copy2(before_zzc, ops_path)
        print(f"已恢复 zzc：{ops_path}")
    else:
        print("未找到 before_zzc.dict.yaml，跳过 zzc 恢复")

    dict_dir = log / "dicts"
    for target in target_paths:
        backup = dict_dir / target.name
        if backup.exists():
            shutil.copy2(backup, target)
            print(f"已恢复码表：{target}")
        else:
            print(f"未找到备份，跳过：{target}")


def main() -> int:
    logs = latest_logs()
    if not logs:
        print("没有可撤回的合并备份。")
        return 0
    log = choose_log(logs)
    if not log:
        print("已取消。")
        return 0
    print(f"将恢复：{log.name}")
    confirm = input("会覆盖当前正式码表和 zzc 文件，确认恢复？输入 YES：").strip()
    if confirm != "YES":
        print("已取消。")
        return 0
    restore_log(log)
    print("撤回完成。")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"撤回合并失败：{exc}", file=sys.stderr)
        raise SystemExit(1)
