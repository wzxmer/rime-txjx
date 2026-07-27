# txjx zzc 脚本说明

## 平台入口

- Windows 合并：双击 `Win_词库合并.exe`
- Windows 撤回合并：双击 `Win_撤回合并.exe`
- macOS 合并：运行 `Mac_词库合并`
- macOS 撤回合并：运行 `Mac_撤回合并`
- Linux 合并：运行 `python3 zzc/Linux_词库合并.py`
- Linux 撤回合并：运行 `python3 zzc/Linux_撤回合并.py`
- iOS 快捷指令合并：免费方案用 a-Shell 运行 `iOS_词库合并.py`，Pythonista 也可运行同一脚本

Windows 只保留 `.exe`。macOS 保留无扩展入口，后续可在 Mac 上转成真正可执行文件。Linux 保留 `.py` 脚本。

旧的 `apply_zzc.py`、`gen_char_parts.py`、`.cmd`、`.bat` 入口已经废弃，不要恢复。

合并入口可以放在方案根目录，也可以放在 `zzc/` 目录。脚本会自动检查脚本所在目录和上级目录里的 `*.zzc.dict.yaml`。`Mac_词库合并` 也支持 `TXJX_ZZC_ROOT` / `TXJX_ZZC_STATE_DIR` 环境变量，供 iOS 快捷指令包装脚本指定最终合并目录和 `zzc_state` 目录。

iOS 入口只做路径配置和调用合并核心，不改合并算法。免费方案见 `a-Shell快捷指令合并说明.md`，Pythonista 方案见 `iOS快捷指令合并说明.md`。首次运行选择最终合并目录：iCloud 用户选 iCloud `RimeUserData` 或方案目录；非 iCloud 用户选应用文件里的 `RimeUserData` 或方案目录。若选择的是 `RimeUserData` 父目录，脚本会向下查找一级；只有一个含 `*.zzc.dict.yaml` 的方案目录时自动使用它，多个方案时要求用户直接选择具体方案目录。`zzc_state` 默认绑定为最终合并目录下的 `zzc_state/`，避免码表写到 iCloud 但 reset/runtime 清到本地应用文件，或反过来。

按 `*.zzc.dict.yaml` 前缀选择合并目标：

- `txjx*` 前缀合并到 `*.dict.yaml` 和 `*.fjcy.dict.yaml`
- `xmjd*` 前缀合并到 `*.cizu.dict.yaml` 和 `*.fjcy.dict.yaml`

Linux/macOS 合并脚本按 Python 3.7+ 兼容写法维护，避免依赖 Python 3.9/3.10 专属运行时 API。

`zzc/` 目录放脚本入口、README、说明附件和撤回备份；运行状态 TSV 放在同级 `zzc_state/`。

## 当前 zzc 状态文件

关键运行状态：

- `../txjx.zzc.dict.yaml` / `../xmjd6.zzc.dict.yaml`：部署可读的持久层，不再是运行时唯一真源。
- `../zzc_state/runtime_ops.tsv`：实时运行时操作记录；每次自造词、替换、删除、置顶、前移、append、restore 都先写这里。
- `../zzc_state/effective_state.tsv`：运行时实际生效快照，普通显示、自造词 collect、删除、置顶、前移、append、restore、completion 都读这里。
- `../zzc_state/runtime_exact.tsv`：兼容缓存占位，不是当前主要显示来源。
- `../zzc_state/cache_version.tsv`：运行时缓存失效标记，用于通知 Lua VM 刷新；Lua 兼容读取旧 `zzc/cache_version.txt`，新写入只使用 `zzc_state`。
- `../zzc_state/runtime_ops_appended.tsv`：记录已追加到 `*.zzc.dict.yaml` 的运行时操作签名，避免清理失败后重复追加。
- `../zzc_state/zzc_reset.tsv`：合并脚本覆盖写入的远端清理标记，通知手机/其他端强制清空本地旧 zzc 状态。
- `../zzc_state/zzc_reset_seen.tsv`：本机已处理的清理标记，避免每次启动重复清理。
- `../zzc_state/char_parts.tsv`：单字拆分索引，Lua 和合并脚本都会用。
- `撤回合并/`：合并前自动备份目录。

工具入口保留在 `zzc/` 根目录，方便用户双击或运行：`Win_*`、`Mac_*`、`Linux_*`。不要保留 `__pycache__/`、`.pyc`、临时打包目录。

## 运行时和重部署行为

Lua 运行中只实时写 `runtime_ops.tsv`，并更新 `effective_state.tsv` 给当前会话显示使用，不立即改写 `*.zzc.dict.yaml`。

键盘收起或 Rime session 结束时，Lua 会把 `zzc_state/runtime_ops.tsv` 追加写入 `*.zzc.dict.yaml`，再清空 `runtime_ops.tsv`、`runtime_exact.tsv` 和 `effective_state.tsv`，并刷新 `cache_version.tsv`。追加成功后会记录 `runtime_ops_appended.tsv` 签名；如果清空运行时文件失败，下次 session 创建时只重试清理，不重复追加同一批操作。

session 创建时不再作为主要写入点，只做上述补偿清理。运行中和 session 结束时都不压缩操作链，以保留完整操作记录；手动合并脚本负责 compact。自造词后如果要让重新部署读取到 `*.zzc.dict.yaml`，先收起键盘结束当前 session，再重新部署。

合并脚本成功后会重置 `*.zzc.dict.yaml` 并覆盖写 `zzc_state/zzc_reset.tsv`，文件只保留 `version/schema/mode/reset_token` 四项，不按历史增长。`reset_token` 是随机 128-bit hex，只做相等比对，不依赖电脑或手机时间。手机端下次键盘唤起时，如果发现新的 `reset_token`，会先强制清空本地 `*.zzc.dict.yaml`、`zzc_state/runtime_ops.tsv`、`zzc_state/runtime_exact.tsv`、`zzc_state/effective_state.tsv`、`zzc_state/runtime_ops_appended.tsv`，再覆盖写 `zzc_state/zzc_reset_seen.tsv` 并刷新 `cache_version.tsv`。reset 完成后可继续正常自造词；同一个 `reset_token` 不会重复清理新周期数据。电脑合并后，手机侧推荐流程是：先收起键盘，再到输入法 App 重新部署，回到输入场景首次唤起键盘自动完成 reset，然后继续造词。

## 合并行为

合并脚本会：

1. 从 `*.danzi.dict.yaml` 重建 `zzc_state/char_parts.tsv`。
2. 读取 `*.zzc.dict.yaml`、`zzc_state/runtime_ops.tsv` 和旧操作文件。
3. 先 compact 操作链，再重放并生成最新 effective 状态。
4. 把 delete、replace、append、restore、order、move 等结果写入正式码表。
5. 备份正式码表和 zzc 状态文件到 `zzc/撤回合并/`。
6. 清理待合并操作文件和运行时缓存。

每次运行合并脚本都会先清理旧撤回备份，只保留最近 3 份；即使本次没有待合并操作，也会执行这项清理。

`+r` / `restore` 行不会无条件重复写入正式码表；只有待处理操作链里存在对应运行时新增事实时，才会作为需要恢复的自造词写回。

## 撤回行为

撤回合并工具用于撤回“词库合并脚本”的结果，会恢复：

- 正式码表备份
- `*.zzc.dict.yaml`
- `zzc_state/runtime_ops.tsv`
- `zzc_state/effective_state.tsv`
- `zzc_state/runtime_exact.tsv`
- `zzc_state/zzc_reset.tsv`
- `zzc_state/zzc_reset_seen.tsv`
- 存在时的旧操作文件

运行时撤回指令和合并撤回工具不是一回事：

- `\--\`：撤回上一次未合并的 zzc 操作。
- `\!!!\` / `\！！！\`：清空全部未合并的 zzc 操作。
- `编码\!!!\` / `编码\！！！\`：同样清空全部未合并的 zzc 操作，编码只作为指令入口。
- `\!` 后继续输入到 `!!!` 再按 `\`：等价 `\!!!\`，清空全部未合并操作。

## 常用运行时指令

- `编码\-数字\`：删除指定序号候选；原码为空时按 `a/i/o/u/v` 标准形码顺序递归补位。
- `编码\-\`：删除当前首选，等价 `编码\-1\`；同码仍有候选时只做原位接替。
- `编码\数字\`：把指定序号候选置顶或前移。
- `编码\+词\`：追加自造词。
- `编码\++数字\`：从可恢复列表恢复指定候选。

普通造词若已存在于后续标准形码，会移动到目标码并清理旧位置。自动补位不处理 `f/s/x` 等无理码、飞键或分类码；一次删除及其全部递归前移可整体撤回。

## 保留 / 不要恢复

应保留：

- `Win_词库合并.exe`
- `Win_撤回合并.exe`
- `Mac_词库合并`
- `Mac_撤回合并`
- `Linux_词库合并.py`
- `Linux_撤回合并.py`
- `../zzc_state/char_parts.tsv`
- `../zzc_state/runtime_exact.tsv`
- `../zzc_state/zzc_reset.tsv`
- `../zzc_state/zzc_reset_seen.tsv`
- 生成后的 `../zzc_state/cache_version.tsv`
- 生成后的 `../zzc_state/runtime_ops.tsv`
- 生成后的 `../zzc_state/effective_state.tsv`
- `指令列表.md`
- `指令列表.png`
- `请根据自己的电脑选择运行合并脚本.txt`

不要恢复：

- `apply_zzc.*`
- `gen_char_parts.*`
- `.cmd`
- `.bat`

