# 天行键自造词

## 参考说明

- 本目录中的自造词思路、Lua 实现、脚本整理流程，均为 `txjx` 方案的一部分。
- 参考、借鉴、转载、二次分发或基于此继续修改时，请明确说明出处来自 `天行键 txjx`。
- 如需对外发布衍生版本，至少应保留出处说明，并附上项目链接：`https://github.com/wzxmer/rime-txjx`

## 当前使用方法

### 1. 起手自造词
1. 输入 `\`
2. 继续输入首个字的编码
3. 用空格选中首个字，不上屏，只进入自造词缓冲
4. 继续输入后续字的编码
5. 中间字默认仍可用空格确认
6. 最后一个字可以直接按 `\`，会先吃当前首选，再结束

示例：
- `\` `hd` 空格 `tco` `\`
- 结果：直接完成 `后调`

### 2. 改当前编码
1. 先正常输入原编码，例如 `hdtc`
2. 按 `\` 进入改码自造词
3. 候选提示会进入 `原词\` 的自造词状态
4. 后续按上面的逐字选字方式继续
5. 最后按 `\` 结束

示例：
- `hdtc` `\` `hd` 空格 `tco` `\`
- 结果：把 `后调` 放到 `hdtc`，原先词条按规则顺延

### 3. 码长结束
- 普通起手自造词仍兼容码长结束
- 支持：`3` `4` `5` `6` `三` `四` `五` `六`
- 二字词支持 4/5/6 码
- 三字词支持 3/4/5/6 码
- 四字及以上支持 4/5/6 码

## 当前文件分工

- `../txjx.zzc.dict.yaml`
  - 自造词真实操作日志兼临时码表
  - 运行期只追加，不做重写
  - 格式：`词汇<Tab>编码 #标识`
  - `+` / `-` / `!` 标识都放在 `#` 注释后，脚本从注释里识别操作类型
- `char_parts.tsv`
  - 单字拆分索引
  - 给 Lua 和脚本快速取码
- `group_*.tsv`
  - 由脚本从 `ops` 重放生成的运行快照
- `index.tsv`
  - 由脚本生成的词到快照组索引
- `apply_zzc.py`
  - 电脑端整理脚本
  - 从 `ops` 提取有效结果
  - 整理顺延词
  - 合并到真实码表
  - 备份并清空 `ops`
- `apply_zzc.cmd` / `apply_zzc.bat`
  - Windows 启动入口
- `gen_char_parts.py`
  - 重建 `char_parts.tsv`
- `gen_char_parts.cmd` / `gen_char_parts.bat`
  - Windows 启动入口

## 脚本行为

运行：

```powershell
py -3 zzc\apply_zzc.py
```

Windows 也可以直接运行：

```powershell
zzc\apply_zzc.cmd
```

或：

```powershell
zzc\apply_zzc.bat
```

执行过程：
1. 重建 `char_parts.tsv`
2. 读取 `txjx.zzc.dict.yaml`
3. 重放自造词和改码操作
4. 生成 `group_*.tsv` 与 `index.tsv`
5. 合并到真实码表 `txjx.dict.yaml` / `txjx.fjcy.dict.yaml`
6. 备份当前 `txjx.zzc.dict.yaml`
7. 重置当前 `txjx.zzc.dict.yaml` 为空码表

## 说明

- 手机端和日常输入只依赖 `ops` 即时追加
- 真实码表整理放到脚本阶段做
- `ops` 清空前会先备份
- 如果 `char_parts.tsv` 缺失，可运行 `gen_char_parts.py`，或直接运行 `apply_zzc.py`
- `cmd` / `bat` 只能在 Windows 用，macOS / Linux 仍需要 `py` 脚本
