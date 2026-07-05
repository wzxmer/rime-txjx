#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.machinery
import importlib.util
import json
import os
import sys
from pathlib import Path

CONFIG_NAME = "ios_zzc_merge_config.json"
CORE_NAME = "Mac_词库合并"


def alert(title: str, message: str) -> None:
    try:
        import console  # type: ignore

        console.alert(title, message, "OK", hide_cancel_button=True)
    except Exception:
        print(f"{title}: {message}")


def confirm(title: str, message: str) -> bool:
    try:
        import console  # type: ignore

        return console.alert(title, message, "继续", "取消", hide_cancel_button=False) == 1
    except Exception:
        answer = input(f"{title}\n{message}\n继续? [y/N] ").strip().lower()
        return answer in {"y", "yes"}


def pick_directory(prompt: str) -> Path:
    alert("选择目录", prompt)
    try:
        import dialogs  # type: ignore

        selected = dialogs.pick_document(types=["public.folder"])
        if isinstance(selected, (list, tuple)):
            selected = selected[0] if selected else None
        if selected:
            return Path(str(selected)).expanduser().resolve()
    except Exception:
        pass
    return Path(input(f"{prompt}\n请输入完整目录路径: ").strip()).expanduser().resolve()


def target_dict_name_options(prefix: str) -> list[list[str]]:
    if prefix.startswith("txjx"):
        return [[f"{prefix}.dict.yaml"], [f"{prefix}.fjcy.dict.yaml"]]
    if prefix.startswith("xmjd"):
        return [[f"{prefix}.cizu.dict.yaml"], [f"{prefix}.fjcy.dict.yaml"]]
    raise ValueError(f"unsupported zzc prefix: {prefix}")


def resolve_target_dicts(root: Path, prefix: str) -> list[Path]:
    out = []
    for options in target_dict_name_options(prefix):
        for name in options:
            path = root / name
            if path.exists():
                out.append(path)
                break
        else:
            out.append(root / options[0])
    return out


def find_ops_candidates(root: Path) -> list[Path]:
    op_candidates = sorted(root.glob("*.zzc.dict.yaml"))
    zzc_dir = root / "zzc"
    if zzc_dir.exists():
        op_candidates += sorted(zzc_dir.glob("*.zzc.dict.yaml"))
    return op_candidates


def normalize_root(root: Path) -> Path:
    if not root.exists() or not root.is_dir():
        raise FileNotFoundError(f"码表目录不存在: {root}")
    if find_ops_candidates(root):
        return root
    child_roots = [
        child
        for child in sorted(root.iterdir())
        if child.is_dir() and find_ops_candidates(child)
    ]
    if len(child_roots) == 1:
        return child_roots[0]
    if child_roots:
        names = ", ".join(child.name for child in child_roots)
        raise FileNotFoundError(f"目录下存在多个方案，请直接选择其中一个: {names}")
    return root


def validate_root(root: Path) -> tuple[Path, str, Path]:
    root = normalize_root(root)
    op_candidates = find_ops_candidates(root)
    if not op_candidates:
        raise FileNotFoundError(f"未找到 *.zzc.dict.yaml: {root}")
    for ops_path in op_candidates:
        schema = ops_path.name[: -len(".zzc.dict.yaml")]
        targets = resolve_target_dicts(root, schema)
        char_dict = root / f"{schema}.danzi.dict.yaml"
        missing = [p for p in targets + [char_dict] if not p.exists()]
        if not missing:
            return root, schema, ops_path
    first = op_candidates[0]
    schema = first.name[: -len(".zzc.dict.yaml")]
    targets = resolve_target_dicts(root, schema)
    char_dict = root / f"{schema}.danzi.dict.yaml"
    missing = [p.name for p in targets + [char_dict] if not p.exists()]
    raise FileNotFoundError(f"码表文件不完整: {', '.join(missing)}")


def load_config(config_path: Path) -> dict[str, str] | None:
    if not config_path.exists():
        return None
    return json.loads(config_path.read_text(encoding="utf-8"))


def save_config(config_path: Path, config: dict[str, str]) -> None:
    config_path.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def configure(config_path: Path, root_arg: str | None, state_arg: str | None, default_state: bool = False) -> dict[str, str]:
    if root_arg:
        root = Path(root_arg).expanduser().resolve()
    else:
        root = pick_directory(
            "请选择最终合并目录，也就是元书/键盘真正读取的 RimeUserData 或方案目录。"
            "iCloud 用户选 iCloud 文件/RimeUserData；非 iCloud 用户选应用文件/RimeUserData。"
        )
    root, schema, ops_path = validate_root(root)

    if state_arg:
        state_dir = Path(state_arg).expanduser().resolve()
        state_mode = "custom"
    else:
        state_dir = root / "zzc_state"
        state_mode = "default"
        if not default_state and not confirm(
            "zzc_state",
            f"默认使用:\n{state_dir}\n\n这能保证清空重置跟最终码表同址。是否使用默认目录?",
        ):
            state_dir = pick_directory("请选择 zzc_state 目录。建议仍放在最终合并目录下。")
            state_mode = "custom"

    try:
        state_dir.relative_to(root)
    except ValueError:
        if not confirm(
            "路径风险",
            "zzc_state 不在最终合并目录内。\n"
            "这可能造成码表合并到一个位置，但 reset/runtime 清理到另一个位置。\n"
            f"码表目录:\n{root}\n\nzzc_state:\n{state_dir}",
        ):
            raise SystemExit(2)

    config = {
        "root_dir": str(root),
        "state_dir": str(state_dir),
        "schema": schema,
        "ops_path": str(ops_path),
        "state_mode": state_mode,
    }
    save_config(config_path, config)
    alert("配置完成", f"码表目录:\n{root}\n\nzzc_state:\n{state_dir}")
    return config


def ensure_config(args: argparse.Namespace, config_path: Path) -> dict[str, str]:
    if args.reset_config and config_path.exists():
        config_path.unlink()
    config = None if args.configure else load_config(config_path)
    if not config:
        return configure(config_path, args.root, args.state, args.default_state)

    root = Path(config["root_dir"]).expanduser().resolve()
    state_dir = Path(config["state_dir"]).expanduser().resolve()
    try:
        root, _, _ = validate_root(root)
    except Exception as exc:
        alert("配置失效", f"{exc}\n请重新选择目录。")
        return configure(config_path, args.root, args.state, args.default_state)
    if config.get("state_mode") == "default":
        state_dir = root / "zzc_state"
    config["root_dir"] = str(root)
    config["state_dir"] = str(state_dir)
    return config


def find_core(script_dir: Path, root: Path) -> Path:
    candidates = [
        script_dir / CORE_NAME,
        root / "zzc" / CORE_NAME,
    ]
    for path in candidates:
        if path.exists():
            return path
    raise FileNotFoundError(f"未找到合并核心 {CORE_NAME}，请把它放在 iOS_词库合并.py 同目录或 root/zzc/")


def run_core(core_path: Path, root: Path, state_dir: Path) -> int:
    os.environ["TXJX_ZZC_ROOT"] = str(root)
    os.environ["TXJX_ZZC_STATE_DIR"] = str(state_dir)
    loader = importlib.machinery.SourceFileLoader("txjx_ios_merge_core", str(core_path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    if spec is None:
        raise RuntimeError(f"cannot load core: {core_path}")
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return int(module.main())


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="iOS shortcut wrapper for txjx/xmjd zzc merge")
    parser.add_argument("--configure", action="store_true", help="重新选择目录并保存配置")
    parser.add_argument("--reset-config", action="store_true", help="删除旧配置后重新选择")
    parser.add_argument("--root", help="最终合并码表目录")
    parser.add_argument("--state", help="zzc_state 目录，默认 root/zzc_state")
    parser.add_argument("--default-state", action="store_true", help="不询问，直接使用 root/zzc_state")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    script_dir = Path(__file__).resolve().parent
    config_path = script_dir / CONFIG_NAME
    config = ensure_config(args, config_path)
    root = Path(config["root_dir"]).expanduser().resolve()
    state_dir = Path(config["state_dir"]).expanduser().resolve()
    core_path = find_core(script_dir, root)
    print(f"iOS zzc root: {root}")
    print(f"iOS zzc_state: {state_dir}")
    return run_core(core_path, root, state_dir)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        alert("合并失败", str(exc))
        print(f"merge failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
