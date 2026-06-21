#!/usr/bin/env python3
from __future__ import annotations

import shutil
import sys
from datetime import datetime
from pathlib import Path
from time import perf_counter

sys.dont_write_bytecode = True


ROOT = Path(__file__).resolve().parents[1]
ZZC_DIR = ROOT / "zzc"
ROLLBACK_DIR = ZZC_DIR / "撤回合并"
ROLLBACK_LOGS = ROLLBACK_DIR / "logs"
INDEX = ZZC_DIR / "index.tsv"
CHAR_PARTS = ZZC_DIR / "char_parts.tsv"
CACHE_VERSION = ZZC_DIR / "cache_version.txt"
KEEP_ROLLBACKS = 3


def find_one(pattern: str) -> Path:
    matches = sorted(ROOT.glob(pattern))
    if not matches:
        raise FileNotFoundError(f"找不到文件：{pattern}")
    return matches[0]


OPS = find_one("*.zzc.dict.yaml")
SCHEMA = OPS.name.removesuffix(".zzc.dict.yaml")
CHAR_DICT = ROOT / f"{SCHEMA}.danzi.dict.yaml"
LEGACY_ROOT_OPS = ROOT / f"{SCHEMA}.zzc.ops.tsv"
LEGACY_OPS = ZZC_DIR / "ops.tsv"
LEGACY_PENDING = ZZC_DIR / "pending.tsv"
TARGET_DICTS = [ROOT / f"{SCHEMA}.dict.yaml", ROOT / f"{SCHEMA}.fjcy.dict.yaml"]

CHAR_PARTS_CACHE: dict[str, list[dict[str, str]]] | None = None


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig")


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(text, encoding="utf-8", newline="\n")
    tmp.replace(path)


def parse_dict_row(line: str) -> tuple[str, str] | None:
    if not line or line.startswith("#"):
        return None
    parts = line.rstrip("\n").split("\t")
    if len(parts) < 2:
        return None
    word, code = parts[0], parts[1]
    if not word or not code:
        return None
    return word, code


def parse_ops_line(line: str) -> dict[str, str] | None:
    text = line.rstrip("\n")
    stripped = text.strip()
    if not stripped or stripped in {"---", "..."}:
        return None
    if stripped.startswith("#") or stripped.startswith("name:") or stripped.startswith("version:"):
        return None
    if stripped.startswith("sort:") or stripped.startswith("use_preset_vocabulary:") or stripped.startswith("columns:"):
        return None
    if stripped.startswith("- ") or stripped.startswith("  - "):
        return None

    parts = text.split("\t")
    if len(parts) >= 2:
        word = parts[0].strip()
        code_part = parts[1].strip()
        code, sep, comment = code_part.partition("#")
        if sep:
            comment_parts = comment.strip().split()
            mark_token = comment_parts[0] if comment_parts else ""
            mark = mark_token[:1]
            code = code.strip()
            if mark in {"+", "-", "!", "^"} and word and code:
                row = {"mark": mark, "word": word, "code": code}
                if mark_token == "+a":
                    row["append"] = "1"
                if len(comment_parts) >= 2 and comment_parts[1].isdigit():
                    row["tx"] = comment_parts[1]
                return row

    if len(parts) == 3:
        mark, word, code = parts
        if mark in {"+", "-", "!", "^"} and word and code:
            return {"mark": mark, "word": word, "code": code}
    return None


def ops_header() -> str:
    return "\n".join(
        [
            "# Rime dictionary",
            "# encoding: utf-8",
            "---",
            f"name: {SCHEMA}.zzc",
            'version: "2026-06-20"',
            "sort: by_weight",
            "use_preset_vocabulary: false",
            "columns:",
            "  - text",
            "  - code",
            "...",
        ]
    ) + "\n"


def rebuild_char_parts() -> int:
    if not CHAR_DICT.exists():
        return 0
    parts: dict[str, list[tuple[str, str, str, str]]] = {}
    for line in read_text(CHAR_DICT).splitlines():
        row = parse_dict_row(line)
        if not row:
            continue
        text, code = row
        if len(text) != 1 or len(code) < 3:
            continue
        value = (code[0], code[1], code[2], code)
        bucket = parts.setdefault(text, [])
        if value not in bucket:
            bucket.append(value)
    lines = [
        f"{text}\t{value[0]}\t{value[1]}\t{value[2]}\t{value[3]}"
        for text, values in sorted(parts.items())
        for value in values
    ]
    write_text(CHAR_PARTS, "\n".join(lines) + ("\n" if lines else ""))
    return len(lines)


def load_ops() -> list[dict[str, str]]:
    ops: list[dict[str, str]] = []
    for source in (OPS, LEGACY_ROOT_OPS, LEGACY_OPS, LEGACY_PENDING):
        if not source.exists():
            continue
        for line in read_text(source).splitlines():
            row = parse_ops_line(line)
            if row:
                ops.append(row)
    return ops


def load_char_parts() -> dict[str, list[dict[str, str]]]:
    global CHAR_PARTS_CACHE
    if CHAR_PARTS_CACHE is not None:
        return CHAR_PARTS_CACHE
    out: dict[str, list[dict[str, str]]] = {}
    if not CHAR_PARTS.exists():
        rebuild_char_parts()
    for line in read_text(CHAR_PARTS).splitlines():
        fields = line.split("\t")
        if len(fields) < 4:
            continue
        text, s, y, p = fields[:4]
        code = fields[4] if len(fields) >= 5 and fields[4] else f"{s}{y}{p}"
        if text and s and y and p:
            entry = {"s": s, "y": y, "p": p, "code": code}
            bucket = out.setdefault(text, [])
            if entry not in bucket:
                bucket.append(entry)
    CHAR_PARTS_CACHE = out
    return out


def same_parts(a: dict[str, str], b: dict[str, str]) -> bool:
    return a["s"] == b["s"] and a["y"] == b["y"] and a["p"] == b["p"]


def hint_matches(entry: dict[str, str], hint: dict[str, str] | str | None) -> bool:
    if hint is None:
        return True
    if isinstance(hint, str):
        code = entry.get("code", "")
        return code.startswith(hint) or hint.startswith(code)
    prefix = hint.get("code_prefix", "")
    if prefix:
        code = entry.get("code", "")
        if not (code.startswith(prefix) or prefix.startswith(code)):
            return False
    for key in ("s", "y", "p"):
        value = hint.get(key, "")
        if value and entry.get(key) != value:
            return False
    return True


def collapse_options(options: list[dict[str, str]]) -> dict[str, str] | None:
    if not options:
        return None
    first = options[0]
    for entry in options[1:]:
        if not same_parts(first, entry):
            return None
    return first


def parts_for_char(ch: str, hint: dict[str, str] | str | None) -> dict[str, str]:
    options = load_char_parts().get(ch, [])
    if not options:
        raise ValueError(f"missing_char:{ch}")
    if len(options) == 1:
        return options[0]
    matched = [entry for entry in options if hint_matches(entry, hint)]
    if len(matched) == 1:
        return matched[0]
    collapsed = collapse_options(matched)
    if collapsed:
        return collapsed
    collapsed = collapse_options(options)
    if collapsed:
        return collapsed
    raise ValueError(f"ambiguous_char:{ch}")


def final_rows_from_ops(ops: list[dict[str, str]]) -> list[tuple[str, str]]:
    rows: list[tuple[str, str]] = []
    seen: set[tuple[str, str]] = set()
    deleted: set[tuple[str, str]] = set()
    for row in reversed(ops):
        key = (row["word"], row["code"])
        if row["mark"] == "!":
            deleted.add(key)
            continue
        if row["mark"] == "^":
            continue
        if key in seen or key in deleted:
            continue
        seen.add(key)
        rows.append(key)
    rows.sort(key=lambda item: (len(item[1]), item[1], item[0]))
    return rows


def latest_order_map(ops: list[dict[str, str]]) -> dict[str, list[str]]:
    latest_tx_by_code: dict[str, str] = {}
    for row in ops:
        if row["mark"] == "^" and row.get("tx"):
            latest_tx_by_code[row["code"]] = row["tx"]
    order_map: dict[str, list[str]] = {}
    seen_by_code: dict[str, set[str]] = {}
    for row in ops:
        if row["mark"] != "^" or latest_tx_by_code.get(row["code"]) != row.get("tx"):
            continue
        seen = seen_by_code.setdefault(row["code"], set())
        if row["word"] in seen:
            continue
        seen.add(row["word"])
        order_map.setdefault(row["code"], []).append(row["word"])
    return order_map


def reorder_dict_lines(lines: list[str], order_map: dict[str, list[str]]) -> list[str]:
    if not order_map:
        return lines
    buckets: dict[str, list[tuple[int, str, str]]] = {}
    for index, line in enumerate(lines):
        row = parse_dict_row(line)
        if row and row[1] in order_map:
            buckets.setdefault(row[1], []).append((index, row[0], line))
    sorted_buckets: dict[str, list[str]] = {}
    for code, rows in buckets.items():
        rank = {word: idx for idx, word in enumerate(order_map.get(code, []))}
        rows.sort(key=lambda item: (rank.get(item[1], 1_000_000), item[0]))
        sorted_buckets[code] = [line for _, _, line in rows]
    out: list[str] = []
    inserted: set[str] = set()
    for line in lines:
        row = parse_dict_row(line)
        if row and row[1] in sorted_buckets:
            code = row[1]
            if code not in inserted:
                out.extend(sorted_buckets[code])
                inserted.add(code)
            continue
        out.append(line)
    return out


def prune_rollback_logs() -> None:
    if not ROLLBACK_LOGS.exists():
        return
    logs = sorted([p for p in ROLLBACK_LOGS.iterdir() if p.is_dir()], key=lambda p: p.name, reverse=True)
    for old in logs[KEEP_ROLLBACKS:]:
        shutil.rmtree(old, ignore_errors=True)


def create_rollback_log(ops_count: int, keep_count: int) -> Path:
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    log_dir = ROLLBACK_LOGS / stamp
    dict_dir = log_dir / "dicts"
    dict_dir.mkdir(parents=True, exist_ok=True)

    manifest = [
        f"created_at={datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        f"schema={SCHEMA}",
        f"ops_count={ops_count}",
        f"keep_count={keep_count}",
        f"root={ROOT}",
        f"ops_path={OPS}",
        "target_paths=" + "|".join(str(p) for p in TARGET_DICTS if p.exists()),
    ]

    if OPS.exists():
        shutil.copy2(OPS, log_dir / "before_zzc.dict.yaml")
    for path in TARGET_DICTS:
        if path.exists():
            shutil.copy2(path, dict_dir / path.name)

    write_text(log_dir / "manifest.txt", "\n".join(manifest) + "\n")
    prune_rollback_logs()
    return log_dir


def merge_into_real_dicts(ops: list[dict[str, str]], keep_rows: list[tuple[str, str]], order_map: dict[str, list[str]]) -> None:
    words_to_remove = {row["word"] for row in ops if row["mark"] in {"+", "-"} and not row.get("append")}
    exact_to_remove = {(row["word"], row["code"]) for row in ops if row["mark"] == "!"}
    for path in TARGET_DICTS:
        if not path.exists():
            continue
        kept: list[str] = []
        removed = 0
        for line in read_text(path).splitlines():
            row = parse_dict_row(line)
            if row:
                word, code = row
                if word in words_to_remove or (word, code) in exact_to_remove:
                    removed += 1
                    continue
            kept.append(line)
        kept = reorder_dict_lines(kept, order_map)
        write_text(path, "\n".join(kept) + "\n")
        print(f"已整理：{path.name}，移除 {removed} 条")
    target = TARGET_DICTS[0]
    if target.exists() and keep_rows:
        with target.open("a", encoding="utf-8", newline="\n") as f:
            for word, code in keep_rows:
                f.write(f"{word}\t{code}\n")
        print(f"已写入最终 zzc 词条：{target.name}，{len(keep_rows)} 条")


def touch_cache_version() -> None:
    stamp = datetime.now().strftime("%Y%m%d%H%M%S%f")
    write_text(CACHE_VERSION, f"{stamp}\n")


def clear_ops() -> None:
    write_text(OPS, ops_header())
    for source in (LEGACY_ROOT_OPS, LEGACY_OPS, LEGACY_PENDING):
        if source.exists():
            write_text(source, "")
    touch_cache_version()


def clear_runtime_cache() -> None:
    removed = 0
    for group_file in ZZC_DIR.glob("group_*.tsv"):
        group_file.unlink()
        removed += 1
    write_text(INDEX, "")
    write_text(ZZC_DIR / "runtime_exact.tsv", "")
    print(f"已清空运行快照：group={removed}")


def main() -> int:
    started = perf_counter()
    print(f"方案目录：{ROOT}")
    char_count = rebuild_char_parts()
    print(f"已重建 char_parts.tsv：{char_count} 字")

    ops = load_ops()
    keep_rows = final_rows_from_ops(ops)
    print(f"待合并操作：{len(ops)} 条；最终写入：{len(keep_rows)} 条")
    if not ops:
        print("没有需要合并的 zzc 操作。")
        return 0

    log_dir = create_rollback_log(len(ops), len(keep_rows))
    print(f"已创建撤回备份：{log_dir.relative_to(ZZC_DIR)}")

    merge_into_real_dicts(ops, keep_rows, latest_order_map(ops))
    clear_ops()
    clear_runtime_cache()
    print(f"合并完成，用时 {perf_counter() - started:.1f} 秒")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"词库合并失败：{exc}", file=sys.stderr)
        raise SystemExit(1)
