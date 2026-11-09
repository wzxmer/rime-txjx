"""Isolated Lua and merge regressions. Usage: python tests/zzc_polyphone_test.py ARTIFACT_DIR [WINDOWS_EXE]."""
from __future__ import annotations

import contextlib
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile

SOURCE = Path(os.environ.get('TXJX_TEST_SOURCE_ROOT', Path(__file__).resolve().parents[1]))
HEADER = '---\nname: txjx\n...\n'
CHAR_PARTS = '谁\te\tb\to\tebo\n谁\te\tw\to\tewo\n送\ts\ty\to\tsyo\n水\te\tb\ta\teba\n松\ts\ty\tv\tsyv\n'


def load_core(script: str, fixture: Path) -> dict:
    (fixture / 'txjx.zzc.dict.yaml').write_text(HEADER, encoding='utf-8')
    namespace = {'__name__': 'isolated_merge_test', '__file__': str(fixture / 'merge.py')}
    path = SOURCE / 'zzc' / script
    overrides = {'TXJX_ZZC_ROOT': str(fixture), 'TXJX_ZZC_STATE_DIR': str(fixture / 'zzc_state')}
    previous = {key: os.environ.get(key) for key in overrides}
    try:
        os.environ.update(overrides)
        exec(compile(path.read_text(encoding='utf-8-sig'), str(path), 'exec'), namespace)
    finally:
        for key, value in previous.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
    return namespace


def check_merge(namespace: dict, initial: list[tuple[str, str]], ops: list[dict], expected: set[tuple[str, str]]) -> None:
    target = namespace['TARGET_DICTS'][0]
    target.write_text(HEADER + ''.join(f'{word}\t{code}\n' for word, code in initial), encoding='utf-8')
    compact = namespace['compact_ops'](ops)
    with contextlib.redirect_stdout(io.StringIO()):
        namespace['merge_into_real_dicts'](compact, namespace['final_rows_from_ops'](compact), namespace['latest_order_map'](compact))
    rows = [namespace['parse_dict_row'](line) for line in target.read_text(encoding='utf-8').splitlines()]
    rows = [row for row in rows if row]
    assert set(rows) == expected, (initial, ops, rows, expected)
    assert len(rows) == len(set(rows)), ('duplicate rows', rows)


def run(artifact: Path, windows_exe: Path | None = None) -> None:
    artifact.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='polyphone-', dir=artifact) as tmp:
        root = Path(tmp)
        lua_root = root / 'lua'
        (lua_root / 'zzc_state').mkdir(parents=True)
        (lua_root / 'zzc_state' / 'char_parts.tsv').write_text(CHAR_PARTS, encoding='utf-8')
        subprocess.run(['lua', str(Path(__file__).with_suffix('.lua')), str(lua_root), str(SOURCE)], check=True)
        for script in ('Linux_词库合并.py', 'Mac_词库合并'):
            fixture = root / script.replace('.', '_')
            fixture.mkdir()
            target = fixture / 'txjx.dict.yaml'
            target.write_text(HEADER, encoding='utf-8')
            namespace = load_core(script, fixture)
            def op(code: str, mark: str = '+', **flags: str) -> dict:
                return {'word': '谁送', 'code': code, 'mark': mark, 'tx': '1', **flags}
            check_merge(namespace, [('谁送', 'ebsy')], [op('ewsy')], {('谁送', 'ebsy'), ('谁送', 'ewsy')})
            check_merge(namespace, [('谁送', 'ebsy'), ('谁送', 'ewsyo')], [op('ewsy')], {('谁送', 'ebsy'), ('谁送', 'ewsy')})
            check_merge(namespace, [('谁送', 'ebsy'), ('谁送', 'ewsy')], [op('ewsyo', '-')], {('谁送', 'ebsy'), ('谁送', 'ewsyo')})
            check_merge(namespace, [], [op('ebsy'), op('ewsy')], {('谁送', 'ebsy'), ('谁送', 'ewsy')})
            check_merge(namespace, [('谁送', 'ebsy'), ('谁送', 'ewsy')], [op('ewsy', '!')], {('谁送', 'ebsy')})
            check_merge(namespace, [('谁送', 'ebsy'), ('谁送', 'ewsy')], [op('ewsy', append='1')], {('谁送', 'ebsy'), ('谁送', 'ewsy')})
            check_merge(namespace, [('谁送', 'ebsy')], [op('ewsy', restore='1')], {('谁送', 'ebsy')})
            check_merge(namespace, [('谁送', 'ebsy')], [op('ewsy'), op('ebsy', '!')], {('谁送', 'ewsy')})
            for word, short, long, other in (
                ('谁送水', 'ese', 'eseo', 'esro'),
                ('谁送水松', 'eses', 'eseso', 'esrs'),
                ('谁，送。', 'ewsy', 'ewsyo', 'ebsy'),
            ):
                check_merge(namespace, [(word, long), (word, other)], [{'word': word, 'code': short, 'mark': '+'}], {(word, short), (word, other)})
            # Full merge + reset + second merge proves persisted readings survive across batches.
            target.write_text(HEADER, encoding='utf-8')
            for code in ('ebsy', 'ewsy'):
                namespace['OPS'].write_text(HEADER + f'谁送\t{code} #+ 1\n', encoding='utf-8')
                with contextlib.redirect_stdout(io.StringIO()):
                    assert namespace['main']() == 0
            text = target.read_text(encoding='utf-8')
            assert '谁送\tebsy\n' in text and '谁送\tewsy\n' in text
            assert namespace['RESET_MARKER'].exists()
            print(f'PASS: {script}: 11 merge cases and two persisted batches')
        if windows_exe:
            fixture = root / 'windows'
            fixture.mkdir()
            import shutil
            exe = fixture / 'Win_词库合并.exe'
            shutil.copy2(windows_exe, exe)
            target = fixture / 'txjx.dict.yaml'
            target.write_text(HEADER, encoding='utf-8')
            for code in ('ebsy', 'ewsy'):
                (fixture / 'txjx.zzc.dict.yaml').write_text(HEADER + f'谁送\t{code} #+ 1\n', encoding='utf-8')
                result = subprocess.run([str(exe)], cwd=fixture, capture_output=True)
                assert result.returncode == 0, result.stdout + result.stderr
            text = target.read_text(encoding='utf-8')
            assert '谁送\tebsy\n' in text and '谁送\tewsy\n' in text
            print('PASS: Windows EXE: two persisted batches preserve both readings')


if __name__ == '__main__':
    run(Path(sys.argv[1]), Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else None)
