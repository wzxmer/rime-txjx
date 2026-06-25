#!/usr/bin/env python3
from __future__ import annotations

import shutil
import sys
from datetime import datetime
from pathlib import Path
from time import perf_counter

sys.dont_write_bytecode = True


KEEP_ROLLBACKS = 3


def find_one(base: Path, pattern: str) -> Path:
    matches = sorted(base.glob(pattern))
    if not matches:
        raise FileNotFoundError(f"missing file: {pattern}")
    return matches[0]


def schema_target_names(schema: str) -> list[str]:
    primary = f"{schema}.cizu.dict.yaml" if schema == "xmjd6" else f"{schema}.dict.yaml"
    return [primary, f"{schema}.fjcy.dict.yaml"]


def has_target_dicts(base: Path, schema: str) -> bool:
    return all((base / name).exists() for name in schema_target_names(schema))


def discover_layout() -> tuple[Path, Path, Path, str]:
    script_path = Path(sys.executable if getattr(sys, "frozen", False) else __file__).resolve()
    start_dir = script_path.parent
    op_candidates = sorted(start_dir.glob("*.zzc.dict.yaml"))
    op_candidates += sorted(start_dir.parent.glob("*.zzc.dict.yaml"))
    seen: set[Path] = set()
    unique_ops: list[Path] = []
    for path in op_candidates:
        resolved = path.resolve()
        if resolved not in seen:
            seen.add(resolved)
            unique_ops.append(resolved)
    if not unique_ops:
        raise FileNotFoundError(f"missing *.zzc.dict.yaml in {start_dir} or {start_dir.parent}")

    for ops_path in unique_ops:
        schema = ops_path.name.removesuffix(".zzc.dict.yaml")
        for root in (ops_path.parent, ops_path.parent.parent):
            if has_target_dicts(root, schema):
                zzc_dir = root / "zzc" if (root / "zzc").exists() else ops_path.parent
                return root, zzc_dir, ops_path, schema
    ops_path = unique_ops[0]
    schema = ops_path.name.removesuffix(".zzc.dict.yaml")
    root = ops_path.parent.parent if ops_path.parent.name == "zzc" else ops_path.parent
    zzc_dir = root / "zzc" if (root / "zzc").exists() else ops_path.parent
    return root, zzc_dir, ops_path, schema


ROOT, ZZC_DIR, OPS, SCHEMA = discover_layout()
ROLLBACK_DIR = ZZC_DIR / "撤回合并"
INDEX = ZZC_DIR / "index.tsv"
RUNTIME_EXACT = ZZC_DIR / "runtime_exact.tsv"
RUNTIME_OPS = ZZC_DIR / "runtime_ops.tsv"
EFFECTIVE_STATE = ZZC_DIR / "effective_state.tsv"
CHAR_PARTS = ZZC_DIR / "char_parts.tsv"
CACHE_VERSION = ZZC_DIR / "cache_version.txt"
CHAR_DICT = ROOT / f"{SCHEMA}.danzi.dict.yaml"
LEGACY_ROOT_OPS = ROOT / f"{SCHEMA}.zzc.ops.tsv"
LEGACY_OPS = ZZC_DIR / "ops.tsv"
LEGACY_PENDING = ZZC_DIR / "pending.tsv"
TARGET_DICTS = [ROOT / name for name in schema_target_names(SCHEMA)]


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
    if stripped.startswith("#") or stripped.startswith("- "):
        return None
    if ":" in stripped and "\t" not in stripped:
        return None

    parts = text.split("\t")
    if len(parts) == 5:
        tx, op, word, code, mark_token = [part.strip() for part in parts]
        mark = mark_token[:1]
        if op and word and code and mark in {"+", "-", "!", "^"}:
            row = {"tx": tx, "op": op, "mark": mark, "word": word, "code": code}
            if mark_token == "+a":
                row["append"] = "1"
            if mark_token == "+r" or op == "restore":
                row["restore"] = "1"
            return row

    if len(parts) >= 2:
        word = parts[0].strip()
        code_part = parts[1].strip()
        code, sep, comment = code_part.partition("#")
        if sep:
            comment_parts = comment.strip().split()
            mark_token = comment_parts[0] if comment_parts else ""
            mark = mark_token[:1]
            code = code.strip()
            if word and code and mark in {"+", "-", "!", "^"}:
                row = {"mark": mark, "word": word, "code": code}
                if mark_token == "+a":
                    row["append"] = "1"
                if mark_token == "+r":
                    row["restore"] = "1"
                if len(comment_parts) >= 2 and comment_parts[1].isdigit():
                    row["tx"] = comment_parts[1]
                return row

    if len(parts) == 3:
        mark, word, code = [part.strip() for part in parts]
        if word and code and mark in {"+", "-", "!", "^"}:
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
    for source in (OPS, RUNTIME_OPS, LEGACY_ROOT_OPS, LEGACY_OPS, LEGACY_PENDING):
        if not source.exists():
            continue
        for line in read_text(source).splitlines():
            row = parse_ops_line(line)
            if row:
                row["source"] = str(source)
                ops.append(row)
    return ops


def latest_state_by_word_code(ops: list[dict[str, str]]) -> dict[tuple[str, str], dict[str, str]]:
    latest: dict[tuple[str, str], dict[str, str]] = {}
    for row in reversed(ops):
        key = (row["word"], row["code"])
        if row["mark"] == "^" or key in latest:
            continue
        latest[key] = row
    return latest


def has_prior_add_fact(ops: list[dict[str, str]], key: tuple[str, str], latest: dict[str, str]) -> bool:
    for row in ops:
        row_key = (row["word"], row["code"])
        if row is latest:
            break
        if row_key != key or row["mark"] == "^":
            continue
        if row["mark"] in {"+", "-"} and not row.get("restore"):
            return True
    return False


def final_rows_from_ops(ops: list[dict[str, str]]) -> list[tuple[str, str]]:
    rows: list[tuple[str, str]] = []
    latest = latest_state_by_word_code(ops)
    for key, row in latest.items():
        if row["mark"] == "!":
            continue
        if row.get("restore") and not has_prior_add_fact(ops, key, row):
            continue
        rows.append(key)
    rows.sort(key=lambda item: (len(item[1]), item[1], item[0]))
    return rows


def latest_order_map(ops: list[dict[str, str]]) -> dict[str, list[str]]:
    latest_state = latest_state_by_word_code(ops)
    latest_tx_by_code: dict[str, str] = {}
    for row in ops:
        if row["mark"] == "^" and row.get("tx"):
            latest_tx_by_code[row["code"]] = row["tx"]

    order_map: dict[str, list[str]] = {}
    seen_by_code: dict[str, set[str]] = {}
    for row in ops:
        if row["mark"] != "^" or latest_tx_by_code.get(row["code"]) != row.get("tx"):
            continue
        state = latest_state.get((row["word"], row["code"]))
        if not state or state["mark"] == "!":
            continue
        seen = seen_by_code.setdefault(row["code"], set())
        if row["word"] in seen:
            continue
        seen.add(row["word"])
        order_map.setdefault(row["code"], []).append(row["word"])
    return order_map


def compact_ops(ops: list[dict[str, str]]) -> list[dict[str, str]]:
    latest = latest_state_by_word_code(ops)
    latest_order_tx_by_code: dict[str, str] = {}
    for row in ops:
        if row["mark"] == "^" and row.get("tx"):
            latest_order_tx_by_code[row["code"]] = row["tx"]

    out: list[dict[str, str]] = []
    for row in ops:
        key = (row["word"], row["code"])
        if row["mark"] != "^" and latest.get(key) is row:
            out.append(row)

    seen_order: set[tuple[str, str]] = set()
    for row in ops:
        if row["mark"] != "^" or latest_order_tx_by_code.get(row["code"]) != row.get("tx"):
            continue
        key = (row["word"], row["code"])
        state = latest.get(key)
        if not state or state["mark"] == "!" or key in seen_order:
            continue
        seen_order.add(key)
        out.append(row)
    return out


def reorder_dict_lines(lines: list[str], order_map: dict[str, list[str]]) -> list[str]:
    if not order_map:
        return lines
    buckets: dict[str, list[tuple[int, str, str]]] = {}
    for index, line in enumerate(lines):
        row = parse_dict_row(line)
        if row and row[1] in order_map:
            word, code = row
            buckets.setdefault(code, []).append((index, word, line))

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


def is_zzc_code(code: str) -> bool:
    return 3 <= len(code) <= 6 and code.isalpha() and code.islower()


def find_insert_index(lines: list[str], code: str) -> int:
    previous_index = -1
    for index, line in enumerate(lines):
        row = parse_dict_row(line)
        if not row:
            continue
        row_code = row[1]
        if not is_zzc_code(row_code):
            continue
        if row_code == code:
            return index
        if row_code > code:
            return previous_index + 1 if previous_index >= 0 else index
        previous_index = index
    return previous_index + 1 if previous_index >= 0 else len(lines)


def build_code_locations(paths: list[Path]) -> dict[str, Path]:
    locations: dict[str, Path] = {}
    for path in paths:
        if not path.exists():
            continue
        for line in read_text(path).splitlines():
            row = parse_dict_row(line)
            if row:
                locations.setdefault(row[1], path)
    return locations


def insert_rows_by_code(
    dict_lines: dict[Path, list[str]],
    keep_rows: list[tuple[str, str]],
    code_locations: dict[str, Path],
) -> dict[Path, int]:
    inserted_by_path: dict[Path, int] = {}
    rows_by_path: dict[Path, list[tuple[str, str]]] = {}
    fallback = TARGET_DICTS[0]
    for word, code in keep_rows:
        path = code_locations.get(code, fallback)
        rows_by_path.setdefault(path, []).append((word, code))

    for path, rows in rows_by_path.items():
        lines = dict_lines.setdefault(path, [])
        rows_by_code: dict[str, list[str]] = {}
        for word, code in rows:
            rows_by_code.setdefault(code, []).append(f"{word}\t{code}")
        for code in sorted(rows_by_code.keys(), reverse=True):
            insert_at = find_insert_index(lines, code)
            for row_line in reversed(rows_by_code[code]):
                lines.insert(insert_at, row_line)
                inserted_by_path[path] = inserted_by_path.get(path, 0) + 1
    return inserted_by_path


def prune_rollback_logs() -> None:
    if not ROLLBACK_DIR.exists():
        return
    logs = sorted(
        [p for p in ROLLBACK_DIR.iterdir() if p.is_dir() and p.name.lower() != "logs"],
        key=lambda p: p.name,
        reverse=True,
    )
    for old in logs[KEEP_ROLLBACKS:]:
        shutil.rmtree(old, ignore_errors=True)


def backup_if_exists(path: Path, backup_dir: Path, manifest: list[str], key: str) -> None:
    if not path.exists():
        return
    backup_dir.mkdir(parents=True, exist_ok=True)
    backup = backup_dir / path.name
    shutil.copy2(path, backup)
    manifest.append(f"{key}={path}|{backup.relative_to(backup_dir.parent)}")


def create_rollback_log(ops_count: int, keep_count: int) -> Path:
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    log_dir = ROLLBACK_DIR / stamp
    dict_dir = log_dir / "dicts"
    state_dir = log_dir / "state"
    dict_dir.mkdir(parents=True, exist_ok=True)
    state_dir.mkdir(parents=True, exist_ok=True)

    manifest = [
        f"created_at={datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        f"schema={SCHEMA}",
        f"ops_count={ops_count}",
        f"keep_count={keep_count}",
        f"root={ROOT}",
        f"ops_path={OPS}",
        "target_paths=" + "|".join(str(p) for p in TARGET_DICTS if p.exists()),
    ]

    backup_if_exists(OPS, state_dir, manifest, "state_path")
    backup_if_exists(RUNTIME_OPS, state_dir, manifest, "state_path")
    backup_if_exists(EFFECTIVE_STATE, state_dir, manifest, "state_path")
    backup_if_exists(RUNTIME_EXACT, state_dir, manifest, "state_path")
    backup_if_exists(INDEX, state_dir, manifest, "state_path")
    backup_if_exists(LEGACY_ROOT_OPS, state_dir, manifest, "state_path")
    backup_if_exists(LEGACY_OPS, state_dir, manifest, "state_path")
    backup_if_exists(LEGACY_PENDING, state_dir, manifest, "state_path")
    if OPS.exists():
        shutil.copy2(OPS, log_dir / "before_zzc.dict.yaml")
    for path in TARGET_DICTS:
        if path.exists():
            shutil.copy2(path, dict_dir / path.name)

    write_text(log_dir / "manifest.txt", "\n".join(manifest) + "\n")
    prune_rollback_logs()
    return log_dir


def merge_into_real_dicts(ops: list[dict[str, str]], keep_rows: list[tuple[str, str]], order_map: dict[str, list[str]]) -> None:
    latest = latest_state_by_word_code(ops)
    words_to_remove = {
        row["word"]
        for row in latest.values()
        if row["mark"] in {"+", "-"} and not row.get("append") and not row.get("restore")
    }
    exact_to_remove = {(word, code) for (word, code), row in latest.items() if row["mark"] == "!"}
    code_locations = build_code_locations(TARGET_DICTS)
    dict_lines: dict[Path, list[str]] = {}

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
        dict_lines[path] = reorder_dict_lines(kept, order_map)
        print(f"cleaned {path.name}: removed={removed}")

    inserted_by_path = insert_rows_by_code(dict_lines, keep_rows, code_locations)
    for path, lines in dict_lines.items():
        write_text(path, "\n".join(lines) + "\n")
    for path, count in inserted_by_path.items():
        print(f"inserted {path.name}: rows={count}")


def touch_cache_version() -> None:
    write_text(CACHE_VERSION, datetime.now().strftime("%Y%m%d%H%M%S%f") + "\n")


def clear_ops() -> None:
    write_text(OPS, ops_header())
    for source in (RUNTIME_OPS, LEGACY_ROOT_OPS, LEGACY_OPS, LEGACY_PENDING):
        if source.exists():
            write_text(source, "")
    touch_cache_version()


def clear_runtime_cache() -> None:
    removed = 0
    for group_file in ZZC_DIR.glob("group_*.tsv"):
        group_file.unlink()
        removed += 1
    write_text(INDEX, "")
    write_text(RUNTIME_EXACT, "")
    write_text(EFFECTIVE_STATE, "")
    print(f"cleared runtime cache: group={removed}")


def main() -> int:
    started = perf_counter()
    print(f"scheme root: {ROOT}")
    char_count = rebuild_char_parts()
    print(f"rebuilt char_parts.tsv: {char_count} chars")

    ops = compact_ops(load_ops())
    keep_rows = final_rows_from_ops(ops)
    print(f"pending ops: {len(ops)}; final rows: {len(keep_rows)}")
    if not ops:
        print("no zzc ops to merge")
        return 0

    log_dir = create_rollback_log(len(ops), len(keep_rows))
    print(f"rollback backup: {log_dir.relative_to(ZZC_DIR)}")

    merge_into_real_dicts(ops, keep_rows, latest_order_map(ops))
    clear_ops()
    clear_runtime_cache()
    print(f"merge done: {perf_counter() - started:.1f}s")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"merge failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
