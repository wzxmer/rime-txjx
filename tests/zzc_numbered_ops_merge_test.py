from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "zzc" / "Linux_词库合并.py"
MERGE_EXE: Path | None = None
OPS_HEADER = """# Rime dictionary
# encoding: utf-8
---
name: {schema}.zzc
version: "2026-06-20"
sort: by_weight
use_preset_vocabulary: false
columns:
  - text
  - code
...
"""


def write_ops(path: Path, schema: str, rows: list[str]) -> None:
    text = OPS_HEADER.format(schema=schema)
    if rows:
        text += "\n".join(rows) + "\n"
    path.write_text(text, encoding="utf-8")


def write_dict(path: Path, schema: str, rows: list[str]) -> None:
    text = f"""# Rime dictionary
---
name: {schema}
version: "test"
sort: by_weight
...
"""
    if rows:
        text += "\n".join(rows) + "\n"
    path.write_text(text, encoding="utf-8")


def invoke_merge(root: Path) -> subprocess.CompletedProcess[str]:
    zzc_dir = root / "zzc"
    zzc_dir.mkdir(exist_ok=True)
    if MERGE_EXE:
        executable = zzc_dir / "Win_词库合并.exe"
        shutil.copy2(MERGE_EXE, executable)
        command = [str(executable)]
    else:
        script = zzc_dir / SCRIPT.name
        shutil.copy2(SCRIPT, script)
        command = [sys.executable, str(script)]
    result = subprocess.run(
        command,
        cwd=root,
        text=True,
        encoding="mbcs" if MERGE_EXE and sys.platform == "win32" else "utf-8",
        errors="replace",
        capture_output=True,
        check=False,
    )
    return result


def run_merge(root: Path) -> subprocess.CompletedProcess[str]:
    result = invoke_merge(root)
    assert result.returncode == 0, result.stdout + result.stderr
    return result


def test_txjx_numbered_files_are_merged_and_removed() -> None:
    with tempfile.TemporaryDirectory() as temp_dir:
        root = Path(temp_dir)
        write_dict(root / "txjx.dict.yaml", "txjx", ["原词\tccc"])
        write_dict(root / "txjx.fjcy.dict.yaml", "txjx.fjcy", ["旧分词\tfff"])
        write_ops(root / "txjx.zzc.dict.yaml", "txjx", ["099\tadd\t主词\tzzz\t+"])
        state_dir = root / "zzc_state"
        state_dir.mkdir()
        (state_dir / "runtime_ops.tsv").write_text("", encoding="utf-8")
        write_ops(root / "txjx.zzc.dict(1).yaml", "txjx", ["100\tadd\t甲词\taaa\t+"])
        write_ops(
            root / "txjx.zzc.dict(2).yaml",
            "txjx",
            ["101\tadd\t乙词\tbbb\t+", "102\tadd\t甲词\taaa\t+", "103\tadd\t新分词\tfff\t+"],
        )
        ignored = root / "txjx.zzc.dict-copy.yaml"
        write_ops(ignored, "txjx", ["103\tadd\t误词\tddd\t+"])

        result = run_merge(root)

        merged = (root / "txjx.dict.yaml").read_text(encoding="utf-8")
        merged_fjcy = (root / "txjx.fjcy.dict.yaml").read_text(encoding="utf-8")
        canonical = root / "txjx.zzc.dict.yaml"
        assert merged.count("主词\tzzz") == 1, merged
        assert merged.count("甲词\taaa") == 1, merged
        assert merged.count("乙词\tbbb") == 1, merged
        assert merged_fjcy.count("新分词\tfff") == 1, merged_fjcy
        assert "误词\tddd" not in merged, merged
        assert canonical.exists()
        assert canonical.read_text(encoding="utf-8") == OPS_HEADER.format(schema="txjx")
        assert not (root / "txjx.zzc.dict(1).yaml").exists()
        assert not (root / "txjx.zzc.dict(2).yaml").exists()
        assert ignored.exists()
        assert "removed numbered zzc files: 2" in result.stdout
        for name in ("runtime_ops.tsv", "runtime_exact.tsv", "effective_state.tsv"):
            assert (state_dir / name).read_bytes() == b"\n"

        rollback_logs = [path for path in (root / "zzc" / "撤回合并").iterdir() if path.is_dir()]
        assert len(rollback_logs) == 1, rollback_logs
        state_backup = rollback_logs[0] / "state"
        assert (state_backup / "txjx.zzc.dict(1).yaml").exists()
        assert (state_backup / "txjx.zzc.dict(2).yaml").exists()


def test_empty_numbered_file_becomes_canonical() -> None:
    with tempfile.TemporaryDirectory() as temp_dir:
        root = Path(temp_dir)
        write_dict(root / "txjx.dict.yaml", "txjx", [])
        write_dict(root / "txjx.fjcy.dict.yaml", "txjx.fjcy", [])
        duplicate = root / "txjx.zzc.dict(7).yaml"
        write_ops(duplicate, "txjx", [])

        result = run_merge(root)

        assert not duplicate.exists()
        assert (root / "txjx.zzc.dict.yaml").read_text(encoding="utf-8") == OPS_HEADER.format(schema="txjx")
        assert "consolidated zzc files: removed=1" in result.stdout


def test_txjx_numbered_only_without_fjcy_target() -> None:
    with tempfile.TemporaryDirectory() as temp_dir:
        root = Path(temp_dir)
        write_dict(root / "txjx.dict.yaml", "txjx", [])
        duplicate = root / "txjx.zzc.dict(1).yaml"
        write_ops(duplicate, "txjx", ["150\tadd\t现场词\tlmn\t+"])

        run_merge(root)

        merged = (root / "txjx.dict.yaml").read_text(encoding="utf-8")
        assert "现场词\tlmn" in merged, merged
        assert not duplicate.exists()
        assert (root / "txjx.zzc.dict.yaml").exists()


def test_xmjd_prefix_is_discovered_without_txjx_special_case() -> None:
    with tempfile.TemporaryDirectory() as temp_dir:
        root = Path(temp_dir)
        write_dict(root / "xmjd6.cizu.dict.yaml", "xmjd6.cizu", [])
        write_dict(root / "xmjd6.fjcy.dict.yaml", "xmjd6.fjcy", [])
        duplicate = root / "xmjd6.zzc.dict(3).yaml"
        write_ops(duplicate, "xmjd6", ["200\tadd\t键道词\txyz\t+"])

        run_merge(root)

        merged = (root / "xmjd6.cizu.dict.yaml").read_text(encoding="utf-8")
        assert "键道词\txyz" in merged, merged
        assert not duplicate.exists()
        assert (root / "xmjd6.zzc.dict.yaml").exists()


def test_merge_failure_keeps_numbered_file() -> None:
    with tempfile.TemporaryDirectory() as temp_dir:
        root = Path(temp_dir)
        (root / "txjx.dict.yaml").mkdir()
        write_dict(root / "txjx.fjcy.dict.yaml", "txjx.fjcy", [])
        duplicate = root / "txjx.zzc.dict(1).yaml"
        write_ops(duplicate, "txjx", ["300\tadd\t保留词\tabc\t+"])

        result = invoke_merge(root)

        assert result.returncode != 0, result.stdout + result.stderr
        assert duplicate.exists()


def test_new_backup_keeps_only_latest_three() -> None:
    with tempfile.TemporaryDirectory() as temp_dir:
        root = Path(temp_dir)
        write_dict(root / "txjx.dict.yaml", "txjx", [])
        write_ops(root / "txjx.zzc.dict.yaml", "txjx", ["400\tadd\t保留三份\tdef\t+"])
        rollback_dir = root / "zzc" / "撤回合并"
        for name in ("20260701-000000", "20260702-000000", "20260703-000000"):
            (rollback_dir / name).mkdir(parents=True)

        run_merge(root)

        remaining = sorted(path.name for path in rollback_dir.iterdir() if path.is_dir())
        assert len(remaining) == 3, remaining
        assert "20260701-000000" not in remaining, remaining
        assert "20260702-000000" in remaining, remaining
        assert "20260703-000000" in remaining, remaining


def main() -> None:
    global MERGE_EXE
    if len(sys.argv) == 3 and sys.argv[1] == "--merge-exe":
        MERGE_EXE = Path(sys.argv[2]).resolve()
    elif len(sys.argv) != 1:
        raise SystemExit("usage: zzc_numbered_ops_merge_test.py [--merge-exe PATH]")
    test_txjx_numbered_files_are_merged_and_removed()
    test_empty_numbered_file_becomes_canonical()
    test_txjx_numbered_only_without_fjcy_target()
    test_xmjd_prefix_is_discovered_without_txjx_special_case()
    test_merge_failure_keeps_numbered_file()
    test_new_backup_keeps_only_latest_three()
    print("zzc numbered ops merge test: ok")


if __name__ == "__main__":
    main()
