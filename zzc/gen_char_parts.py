#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

sys.dont_write_bytecode = True


ROOT = Path(__file__).resolve().parents[1]
ZZC_DIR = ROOT / "zzc"
CHAR_PARTS = ZZC_DIR / "char_parts.tsv"
CHAR_DICT = ROOT / "txjx.danzi.dict.yaml"


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig")


def write_text(path: Path, text: str) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(text, encoding="utf-8", newline="\n")
    tmp.replace(path)


def parse_dict_row(line: str) -> tuple[str, str] | None:
    parts = line.rstrip("\n").split("\t")
    if len(parts) < 2:
        return None
    word, code = parts[0], parts[1]
    if not word or not code or word.startswith("#"):
        return None
    return word, code


def is_single_char(text: str) -> bool:
    return len(text) == 1


def rebuild_char_parts() -> int:
    if not CHAR_DICT.exists():
        return 0

    parts: dict[str, list[tuple[str, str, str, str]]] = {}
    for line in read_text(CHAR_DICT).splitlines():
        row = parse_dict_row(line)
        if not row:
            continue
        text, code = row
        if not is_single_char(text) or len(code) < 3:
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
    write_text(CHAR_PARTS, "\n".join(lines) + "\n")
    return len(lines)


def main() -> int:
    count = rebuild_char_parts()
    print(f"已生成 zzc/char_parts.tsv：{count} 字")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"gen_char_parts 失败：{exc}", file=sys.stderr)
        raise SystemExit(1)
