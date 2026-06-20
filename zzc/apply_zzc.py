#!/usr/bin/env python3
from __future__ import annotations

import shutil
import sys
from time import perf_counter
from datetime import datetime
from pathlib import Path

sys.dont_write_bytecode = True

from gen_char_parts import rebuild_char_parts


ROOT = Path(__file__).resolve().parents[1]
ZZC_DIR = ROOT / "zzc"
OPS = ROOT / "txjx.zzc.dict.yaml"
LEGACY_ROOT_OPS = ROOT / "txjx.zzc.ops.tsv"
LEGACY_OPS = ZZC_DIR / "ops.tsv"
LEGACY_PENDING = ZZC_DIR / "pending.tsv"
INDEX = ZZC_DIR / "index.tsv"
TARGET_DICTS = [ROOT / "txjx.dict.yaml", ROOT / "txjx.fjcy.dict.yaml"]
CHAR_PARTS = ZZC_DIR / "char_parts.tsv"
OPS_BACKUP_DIR = ZZC_DIR / "ops_backup"

SOURCE_ROW_CACHE: dict[str, list[dict[str, str]]] = {}
CHAR_PARTS_CACHE: dict[str, list[dict[str, str]]] | None = None


class PerfLog:
    def __init__(self) -> None:
        self.start = perf_counter()
        self.last = self.start

    def lap(self, label: str, **fields: object) -> None:
        now = perf_counter()
        details = " ".join(f"{key}={value}" for key, value in fields.items())
        suffix = f" {details}" if details else ""
        print(f"[perf] {label} +{now - self.last:.3f}s total={now - self.start:.3f}s{suffix}")
        self.last = now


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig")


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(text, encoding="utf-8", newline="\n")
    tmp.replace(path)


def ops_header() -> str:
    return "\n".join(
        [
            "# Rime dictionary",
            "# encoding: utf-8",
            "---",
            "name: txjx.zzc",
            'version: "2026-06-20"',
            "sort: by_weight",
            "use_preset_vocabulary: false",
            "columns:",
            "  - text",
            "  - code",
            "...",
        ]
    ) + "\n"


def parse_ops_line(line: str) -> dict[str, str] | None:
    text = line.rstrip("\n")
    stripped = text.strip()
    if not stripped or stripped in {"---", "..."} or stripped.startswith("# Rime") or stripped.startswith("# encoding"):
        return None
    if stripped.startswith("#"):
        return None
    elif ":" in stripped and "\t" not in stripped:
        return None
    parts = text.split("\t")
    if len(parts) >= 2:
        word = parts[0].strip()
        code_part = parts[1].strip()
        code, sep, comment = code_part.partition("#")
        if sep:
            comment_parts = comment.strip().split()
            mark = comment_parts[0][:1] if comment_parts else ""
            code = code.strip()
            if mark in {"+", "-", "!", "^"} and word and code:
                row = {"mark": mark, "word": word, "code": code}
                if len(comment_parts) >= 2 and comment_parts[1].isdigit():
                    row["tx"] = comment_parts[1]
                return row
    if len(parts) != 3:
        return None
    mark, word, code = parts
    if mark not in {"+", "-", "!", "^"} or not word or not code:
        return None
    return {"mark": mark, "word": word, "code": code}


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
    for line in read_text(CHAR_PARTS).splitlines():
        parts = line.split("\t")
        if len(parts) < 4:
            continue
        text, s, y, p = parts[:4]
        code = parts[4] if len(parts) >= 5 and parts[4] else f"{s}{y}{p}"
        if not text or not s or not y or not p:
            continue
        bucket = out.setdefault(text, [])
        entry = {"s": s, "y": y, "p": p, "code": code}
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


def hint_list_for_word(word: str, code: str) -> list[dict[str, str] | None]:
    chars = list(word)
    n = len(chars)
    out: list[dict[str, str] | None] = [None] * n
    code = code or ""
    if n == 1:
        out[0] = {"code_prefix": code}
    elif n == 2:
        out[0] = {"s": code[0:1], "y": code[1:2]}
        out[1] = {"s": code[2:3], "y": code[3:4]}
        if len(code) >= 5:
            out[0]["p"] = code[4:5]
        if len(code) >= 6:
            out[1]["p"] = code[5:6]
    elif n == 3:
        out[0] = {"s": code[0:1]}
        out[1] = {"s": code[1:2]}
        out[2] = {"s": code[2:3]}
        if len(code) >= 4:
            out[0]["p"] = code[3:4]
        if len(code) >= 5:
            out[1]["p"] = code[4:5]
        if len(code) >= 6:
            out[2]["p"] = code[5:6]
    elif n >= 4:
        out[0] = {"s": code[0:1]}
        out[1] = {"s": code[1:2]}
        out[2] = {"s": code[2:3]}
        out[-1] = {"s": code[3:4]}
        if len(code) >= 5:
            out[0]["p"] = code[4:5]
        if len(code) >= 6:
            out[1]["p"] = code[5:6]
    return out


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


def items_from_text(text: str, hints: list[dict[str, str] | None] | None = None) -> list[dict[str, dict[str, str]]]:
    items: list[dict[str, dict[str, str]]] = []
    for idx, ch in enumerate(text):
        hint = hints[idx] if hints and idx < len(hints) else None
        items.append({"text": ch, "parts": parts_for_char(ch, hint)})
    return items


def code_at(items: list[dict[str, dict[str, str]]]) -> str:
    n = len(items)
    if n == 2:
        return (
            items[0]["parts"]["s"] + items[0]["parts"]["y"] +
            items[1]["parts"]["s"] + items[1]["parts"]["y"] +
            items[0]["parts"]["p"] + items[1]["parts"]["p"]
        )
    if n == 3:
        return (
            items[0]["parts"]["s"] + items[1]["parts"]["s"] + items[2]["parts"]["s"] +
            items[0]["parts"]["p"] + items[1]["parts"]["p"] + items[2]["parts"]["p"]
        )
    return (
        items[0]["parts"]["s"] + items[1]["parts"]["s"] + items[2]["parts"]["s"] +
        items[-1]["parts"]["s"] + items[0]["parts"]["p"] + items[1]["parts"]["p"]
    )


def append_next_code(word: str, code: str) -> str | None:
    if len(code) >= 6:
        return None
    items = items_from_text(word, hint_list_for_word(word, code))
    full = code_at(items)
    if not full.startswith(code) or len(full) <= len(code):
        return None
    return full[: len(code) + 1]


def read_source_rows(prefix: str) -> list[dict[str, str]]:
    cached = SOURCE_ROW_CACHE.get(prefix)
    if cached is not None:
        return [row.copy() for row in cached]
    rows: list[dict[str, str]] = []
    for path in TARGET_DICTS:
        if not path.exists():
            continue
        for line in read_text(path).splitlines():
            row = parse_dict_row(line)
            if not row:
                continue
            word, code = row
            if code.startswith(prefix):
                rows.append({"mark": "src", "word": word, "code": code, "original": code})
    SOURCE_ROW_CACHE[prefix] = [row.copy() for row in rows]
    return [row.copy() for row in rows]


def apply_snapshot(rows: list[dict[str, str]], snapshot: list[dict[str, str]]) -> None:
    for row in snapshot:
        if row["mark"] == "!":
            rows[:] = [cur for cur in rows if not (cur["word"] == row["word"] and cur["code"] == row["code"])]
            continue
        rows[:] = [cur for cur in rows if cur["word"] != row["word"]]
        rows.append({"mark": row["mark"], "word": row["word"], "code": row["code"], "original": row["code"]})


def code_taken(rows: list[dict[str, str]], code: str) -> dict[str, str] | None:
    for row in rows:
        if row["mark"] != "!" and row["code"] == code:
            return row
    return None


def remove_word(rows: list[dict[str, str]], word: str) -> list[dict[str, str]]:
    removed = [row for row in rows if row["word"] == word and row["mark"] != "!"]
    rows[:] = [row for row in rows if not (row["word"] == word and row["mark"] != "!")]
    return removed


def push_down(rows: list[dict[str, str]], row: dict[str, str], visiting: set[str]) -> None:
    word = row["word"]
    if word in visiting:
        raise ValueError("code_cycle")
    visiting.add(word)
    next_code = append_next_code(word, row["code"])
    if next_code is None:
        visiting.remove(word)
        return
    blocked = code_taken(rows, next_code)
    if blocked is not None:
        push_down(rows, blocked, visiting)
    row["code"] = next_code
    if row["mark"] != "+":
        row["mark"] = "-"
    visiting.remove(word)


def flatten_snapshot(snapshot_map: dict[str, list[dict[str, str]]]) -> list[dict[str, str]]:
    out: list[dict[str, str]] = []
    for prefix in sorted(snapshot_map):
        for row in snapshot_map[prefix]:
            out.append({"mark": row["mark"], "word": row["word"], "code": row["code"]})
    return out


def replay_ops(ops: list[tuple[str, str]]) -> tuple[dict[str, list[dict[str, str]]], dict[str, str]]:
    snapshot_map: dict[str, list[dict[str, str]]] = {}
    index: dict[str, str] = {}
    for word, code in ops:
        prefix = code
        old_prefix = index.get(word)
        if old_prefix and old_prefix != prefix:
            snapshot_map[old_prefix] = [row.copy() for row in snapshot_map.get(old_prefix, []) if row["word"] != word]
        rows = read_source_rows(prefix)
        apply_snapshot(rows, snapshot_map.get(prefix, []))
        removed = remove_word(rows, word)
        for row in removed:
            if row["code"] != code:
                rows.append({"mark": "!", "word": row["word"], "code": row["code"], "original": row.get("original", row["code"])})
        blocked = code_taken(rows, code)
        if blocked is not None:
            push_down(rows, blocked, set())
        rows.append({"mark": "+", "word": word, "code": code, "original": code})
        snapshot = [
            {"mark": row["mark"], "word": row["word"], "code": row["code"]}
            for row in rows
            if row["mark"] in {"+", "-", "!"}
        ]
        snapshot_map[prefix] = snapshot
        for row in snapshot:
            if row["mark"] in {"+", "-"}:
                index[row["word"]] = prefix
    return snapshot_map, index


def final_rows(snapshot_map: dict[str, list[dict[str, str]]]) -> list[tuple[str, str]]:
    rows: list[tuple[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for prefix in sorted(snapshot_map):
        for row in snapshot_map[prefix]:
            if row["mark"] == "!":
                continue
            key = (row["word"], row["code"])
            if key not in seen:
                seen.add(key)
                rows.append(key)
    rows.sort(key=lambda item: (len(item[1]), item[1], item[0]))
    return rows


def write_runtime_cache(snapshot_map: dict[str, list[dict[str, str]]], index: dict[str, str]) -> None:
    ZZC_DIR.mkdir(parents=True, exist_ok=True)
    index_lines = [f"{word}\t{prefix}" for word, prefix in sorted(index.items(), key=lambda item: (item[1], item[0]))]
    write_text(INDEX, "\n".join(index_lines) + ("\n" if index_lines else ""))
    for old_group in ZZC_DIR.glob("group_*.tsv"):
        old_group.unlink()
    for prefix in sorted(snapshot_map):
        group_lines = [f"{row['mark']}\t{row['word']}\t{row['code']}" for row in snapshot_map[prefix]]
        write_text(ZZC_DIR / f"group_{prefix}.tsv", "\n".join(group_lines) + ("\n" if group_lines else ""))


def clear_runtime_cache() -> None:
    ZZC_DIR.mkdir(parents=True, exist_ok=True)
    removed = 0
    for group_file in ZZC_DIR.glob("group_*.tsv"):
        group_file.unlink()
        removed += 1
    write_text(INDEX, "")
    runtime_exact = ZZC_DIR / "runtime_exact.tsv"
    write_text(runtime_exact, "")
    print(f"已清空 runtime cache：group={removed} index=0")


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
            word, code = row
            buckets.setdefault(code, []).append((index, word, line))

    sorted_buckets: dict[str, list[str]] = {}
    for code, rows in buckets.items():
        order = order_map.get(code, [])
        rank = {word: idx for idx, word in enumerate(order)}
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


def merge_into_real_dicts(snapshot_rows: list[dict[str, str]], keep_rows: list[tuple[str, str]], order_map: dict[str, list[str]]) -> None:
    t0 = perf_counter()
    if not snapshot_rows:
        print("txjx.zzc.dict.yaml 为空，已跳过真实码表合并。")
        return
    words_to_remove = {row["word"] for row in snapshot_rows if row["mark"] in {"+", "-"}}
    exact_to_remove = {(row["word"], row["code"]) for row in snapshot_rows if row["mark"] == "!"}
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    for path in TARGET_DICTS:
        if not path.exists():
            continue
        path_t0 = perf_counter()
        backup = path.with_name(path.name + f".bak-{stamp}")
        shutil.copy2(path, backup)
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
        print(f"已备份并清理：{path.name} -> {backup.name}")
        print(f"[perf] merge_dict file={path.name} elapsed={perf_counter() - path_t0:.3f}s kept={len(kept)} removed={removed}")
    target = TARGET_DICTS[0]
    if target.exists() and keep_rows:
        write_t0 = perf_counter()
        with target.open("a", encoding="utf-8", newline="\n") as f:
            for word, code in keep_rows:
                f.write(f"{word}\t{code}\n")
        print(f"已写入最终 zzc 词条：{target.name}，{len(keep_rows)} 条")
        print(f"[perf] append_keep_rows file={target.name} elapsed={perf_counter() - write_t0:.3f}s rows={len(keep_rows)}")
    print(f"[perf] merge_into_real_dicts_inner elapsed={perf_counter() - t0:.3f}s")


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


def backup_and_clear_ops() -> None:
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backed_up = False
    if OPS.exists():
        text = read_text(OPS)
        if any(parse_ops_line(line) for line in text.splitlines()):
            backup = ROOT / f"txjx.zzc-{stamp}.dict.yaml"
            write_text(backup, text if text.endswith("\n") else text + "\n")
            print(f"已备份 ops：{OPS.name} -> {backup.relative_to(ROOT)}")
            backed_up = True
        write_text(OPS, ops_header())
        print(f"已清空 ops：{OPS.relative_to(ROOT)}")
    for source in (LEGACY_ROOT_OPS, LEGACY_OPS, LEGACY_PENDING):
        if not source.exists():
            continue
        write_text(source, "")
        print(f"已清空 ops：{source.relative_to(ROOT)}")
    if not backed_up:
        print("ops 为空，本次未生成 ops 备份。")


def main() -> int:
    perf = PerfLog()
    char_count = rebuild_char_parts()
    print(f"已生成 zzc/char_parts.tsv：{char_count} 字")
    perf.lap("rebuild_char_parts", chars=char_count)
    ops = load_ops()
    print(f"已读取 ops：{len(ops)} 条")
    marks = {mark: sum(1 for row in ops if row["mark"] == mark) for mark in ("+", "-", "!", "^")}
    tx_count = len({row.get("tx", "") for row in ops if row.get("tx")})
    perf.lap("load_ops", rows=len(ops), plus=marks["+"], minus=marks["-"], bang=marks["!"], order=marks["^"], tx=tx_count)
    order_map = latest_order_map(ops)
    keep_rows = final_rows_from_ops(ops)
    print(f"已解析最终词条：rows={len(keep_rows)}")
    perf.lap("final_rows_from_ops", rows=len(keep_rows))
    merge_into_real_dicts(ops, keep_rows, order_map)
    perf.lap("merge_into_real_dicts", rows=len(keep_rows))
    backup_and_clear_ops()
    perf.lap("backup_and_clear_ops")
    clear_runtime_cache()
    perf.lap("clear_runtime_cache")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"apply_zzc 失败：{exc}", file=sys.stderr)
        raise SystemExit(1)
