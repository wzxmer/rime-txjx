# iOS 快捷指令合并 zzc

适用：iOS 16、Pythonista、当前 `txjx/zzc/iOS_词库合并.py`。

## 文件准备

把下面两个文件放在 Pythonista 同一个目录，或保留在方案目录的 `zzc/` 下：

- `iOS_词库合并.py`
- `Mac_词库合并`

`iOS_词库合并.py` 只负责 iOS 配置和启动；真正合并仍由 `Mac_词库合并` 执行。

## 首次运行

第一次先在 Pythonista 内运行 `iOS_词库合并.py`，完成路径配置。

选择最终合并目录时：

- 使用 iCloud：选 iCloud 文件里的 `RimeUserData` 或其中的方案目录。
- 不使用 iCloud：选元书应用文件里的 `RimeUserData` 或其中的方案目录。

如果选择 `RimeUserData`，脚本会向下查找一级；只有一个方案目录时自动进入，多个方案时需要你直接选择具体方案目录。

`zzc_state` 默认使用最终合并目录下的 `zzc_state/`。除非明确知道自己在做什么，不要改成别的目录。

脚本会保存：

- `ios_zzc_merge_config.json`

后续快捷指令直接使用这个配置。

## 快捷指令做法一：URL Scheme 推荐

1. 打开快捷指令 App。
2. 新建快捷指令，命名如“合并 txjx zzc”。
3. 添加“URL”动作。
4. 填入：

```text
pythonista3://iOS_%E8%AF%8D%E5%BA%93%E5%90%88%E5%B9%B6.py?action=run
```

5. 添加“打开 URL”动作。
6. 保存。

之后点快捷指令即可运行合并。

如要重新选择目录，临时在 Pythonista 里运行：

```text
iOS_词库合并.py --configure
```

或删除同目录的 `ios_zzc_merge_config.json` 后重新运行。

## 快捷指令做法二：Pythonista 动作

如果快捷指令里能搜到 Pythonista 原生动作，也可以这样做：

1. 新建快捷指令。
2. 搜索 `Pythonista`。
3. 添加 `Run Pythonista Script` / `运行 Pythonista 脚本`。
4. Script 选择 `iOS_词库合并.py`。
5. 打开 `Run in Pythonista`。
6. 可打开 `Auto-Return to Shortcuts`。
7. 保存。

如果搜不到这个动作，直接用 URL Scheme 做法。文件放在子目录时，需要按 Pythonista 脚本库内相对路径调整 URL，并做 URL encode。

## iCloud 和非 iCloud 路径原则

iCloud 模式：

- 最终码表目录选 iCloud。
- `zzc_state` 也在 iCloud 同一棵目录。
- 合并后重新部署，元书会把 iCloud 变化带入应用文件，再进入键盘文件。

非 iCloud 模式：

- 最终码表目录选应用文件。
- `zzc_state` 也在应用文件同一棵目录。
- 不碰 iCloud。

禁止混用：

- 码表目录在 iCloud，`zzc_state` 在 Pythonista 本地。
- 码表目录在应用文件，`zzc_state` 在 iCloud。
- 用脚本所在目录推断数据目录。

脚本所在目录只用于找合并核心和保存配置，不代表最终数据路径。
