from __future__ import annotations

import importlib.util
import tempfile
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "zzc" / "Linux_词库合并.py"


def load_merge_module():
    spec = importlib.util.spec_from_file_location("zzc_merge", SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> None:
    module = load_merge_module()
    with tempfile.TemporaryDirectory() as temp_dir:
        rollback_dir = Path(temp_dir)
        for name in (
            "20260710-221254",
            "20260720-191600",
            "20260722-015335",
            "20260722-015429",
        ):
            (rollback_dir / name).mkdir()
        (rollback_dir / "logs").mkdir()

        removed = module.prune_rollback_logs(rollback_dir)

        remaining = sorted(path.name for path in rollback_dir.iterdir())
        assert [path.name for path in removed] == ["20260710-221254"], remaining
        assert remaining == [
            "20260720-191600",
            "20260722-015335",
            "20260722-015429",
            "logs",
        ], remaining

    print("zzc rollback retention test: ok")


if __name__ == "__main__":
    main()
