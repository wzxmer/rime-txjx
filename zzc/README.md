# txjx zzc 脚本说明

## 平台入口

- Windows 合并：双击 `Win_词库合并.exe`
- Windows 撤回合并：双击 `Win_撤回合并.exe`
- macOS 合并：运行 `Mac_词库合并`
- macOS 撤回合并：运行 `Mac_撤回合并`
- Linux 合并：运行 `python3 zzc/Linux_词库合并.py`
- Linux 撤回合并：运行 `python3 zzc/Linux_撤回合并.py`

Windows 只保留 `.exe`。macOS 保留无扩展入口，后续可在 Mac 上转成真正可执行文件。Linux 保留 `.py` 脚本。

旧的 `apply_zzc.py`、`gen_char_parts.py`、`.cmd`、`.bat` 入口已经废弃，不要恢复。

合并入口可以放在方案根目录，也可以放在 `zzc/` 目录。脚本会自动检查脚本所在目录和上级目录里的 `*.zzc.dict.yaml`。

按 `*.zzc.dict.yaml` 前缀选择合并目标：

- `txjx*` 前缀合并到 `*.dict.yaml` 和 `*.fjcy.dict.yaml`
- `xmjd*` 前缀合并到 `*.cizu.dict.yaml` 和 `*.fjcy.dict.yaml`

Linux/macOS 合并脚本按 Python 3.7+ 兼容写法维护，避免依赖 Python 3.9/3.10 专属运行时 API。

## 当前 zzc 状态文件

- `../txjx.zzc.dict.yaml` / `../xmjd6.zzc.dict.yaml`：部署可读的持久层，不再是运行时唯一真源。
- `runtime_ops.tsv`：实时运行时操作记录；每次自造词、替换、删除、置顶、前移、append、restore 都先写这里。
- `effective_state.tsv`：运行时实际生效快照，普通显示、自造词 collect、删除、置顶、前移、append、restore、completion 都读这里。
- `runtime_exact.tsv`：兼容缓存占位，不是当前主要显示来源。
- `index.tsv`：兼容索引占位。
- `cache_version.txt`：运行时缓存失效标记，用于通知 Lua VM 刷新。
- `runtime_ops_appended.tsv`：记录已追加到 `*.zzc.dict.yaml` 的运行时操作签名，避免清理失败后重复追加。
- `char_parts.tsv`：单字拆分索引，Lua 和合并脚本都会用。
- `撤回合并/`：合并前自动备份目录。

## 运行时和重部署行为

Lua 运行中只实时写 `runtime_ops.tsv`，并更新 `effective_state.tsv` 给当前会话显示使用，不立即改写 `*.zzc.dict.yaml`。

键盘收起或 Rime session 结束时，Lua 会把 `runtime_ops.tsv` 追加写入 `*.zzc.dict.yaml`，再清空 `runtime_ops.tsv`、`runtime_exact.tsv`、`index.tsv` 和 `effective_state.tsv`，并刷新 `cache_version.txt`。追加成功后会记录 `runtime_ops_appended.tsv` 签名；如果清空运行时文件失败，下次 session 创建时只重试清理，不重复追加同一批操作。

session 创建时不再作为主要写入点，只做上述补偿清理。运行中和 session 结束时都不压缩操作链，以保留完整操作记录；手动合并脚本负责 compact。自造词后如果要让重新部署读取到 `*.zzc.dict.yaml`，先收起键盘结束当前 session，再重新部署。

## 合并行为

合并脚本会：

1. 从 `*.danzi.dict.yaml` 重建 `char_parts.tsv`。
2. 读取 `*.zzc.dict.yaml`、`runtime_ops.tsv` 和旧操作文件。
3. 先 compact 操作链，再重放并生成最新 effective 状态。
4. 把 delete、replace、append、restore、order、move 等结果写入正式码表。
5. 备份正式码表和 zzc 状态文件到 `zzc/撤回合并/`。
6. 清理待合并操作文件和运行时缓存。

`+r` / `restore` 行不会无条件重复写入正式码表；只有待处理操作链里存在对应运行时新增事实时，才会作为需要恢复的自造词写回。

## 撤回行为

撤回合并工具用于撤回“词库合并脚本”的结果，会恢复：

- 正式码表备份
- `*.zzc.dict.yaml`
- `runtime_ops.tsv`
- `effective_state.tsv`
- `runtime_exact.tsv`
- `index.tsv`
- 存在时的旧操作文件

运行时撤回指令和合并撤回工具不是一回事：

- `\--\`：撤回上一次未合并的 zzc 操作。
- `\!!!\` / `\！！！\`：清空全部未合并的 zzc 操作。
- `\!` 后继续输入到 `!!!` 再按 `\`：等价 `\!!!\`，清空全部未合并操作。

## 常用运行时指令

- `编码\-数字\`：删除指定序号候选。
- `编码\-\`：删除当前首选，等价 `编码\-1\`。
- `编码\数字\`：把指定序号候选置顶或前移。
- `编码\+词\`：追加自造词。
- `编码\++数字\`：从可恢复列表恢复指定候选。

## 保留 / 不要恢复

应保留：

- `Win_词库合并.exe`
- `Win_撤回合并.exe`
- `Mac_词库合并`
- `Mac_撤回合并`
- `Linux_词库合并.py`
- `Linux_撤回合并.py`
- `char_parts.tsv`
- `index.tsv`
- `runtime_exact.tsv`
- 生成后的 `cache_version.txt`
- 生成后的 `runtime_ops.tsv`
- 生成后的 `effective_state.tsv`
- `指令列表.md`
- `指令列表.png`

不要恢复：

- `apply_zzc.*`
- `gen_char_parts.*`
- `.cmd`
- `.bat`
