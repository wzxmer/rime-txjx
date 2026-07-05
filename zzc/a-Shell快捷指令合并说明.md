# a-Shell 免费方案：iOS 快捷指令合并 zzc

适用：iOS 16、a-Shell、当前 `iOS_词库合并.py`。

## 安装

App Store 安装 `a-Shell`。

## 文件准备

把下面两个文件放进 a-Shell 可访问目录，例如 `~/Documents/txjx-zzc/`：

- `iOS_词库合并.py`
- `Mac_词库合并`

也可以直接放在方案目录的 `zzc/` 下，只要 a-Shell 能访问。

## 首次配置

打开 a-Shell，进入脚本所在目录：

```sh
cd ~/Documents/txjx-zzc
```

选择最终合并目录：

```sh
pickFolder
```

在文件选择器里选择最终合并目录。a-Shell 会进入该目录并保存书签；如果提示符还没变化，按一次回车。确认当前位置：

```sh
pwd
```

回到脚本所在目录并保存配置：

```sh
root=$(pwd)
cd ~/Documents/txjx-zzc
python3 iOS_词库合并.py --root "$root" --default-state
```

选择目录规则：

- 使用 iCloud：选 iCloud 文件里的 `RimeUserData` 或其中的方案目录。
- 不使用 iCloud：选元书应用文件里的 `RimeUserData` 或其中的方案目录。

如果选择 `RimeUserData`，脚本会向下查找一级；只有一个方案目录时自动进入，多个方案时要求你直接选择具体方案目录。

`--default-state` 表示直接使用最终目录下的 `zzc_state/`，避免把 reset/runtime 清到错误位置。

## 日常运行

配置完成后，日常只需要：

```sh
cd ~/Documents/txjx-zzc
python3 iOS_词库合并.py
```

## 快捷指令制作

1. 打开快捷指令 App。
2. 新建快捷指令，命名如“合并 txjx zzc”。
3. 添加 a-Shell 的运行命令动作。如果能搜到 `a-Shell`，选择运行命令/Run Command。
4. 运行方式选 `In App`，不要选 `In Extension`。外部 iCloud/应用文件目录通常需要主 App 才能稳定访问。
5. 命令填：

```sh
cd ~/Documents/txjx-zzc && python3 iOS_词库合并.py; open shortcuts://
```

6. 保存。

如果快捷指令里没有 a-Shell 动作，用 URL 方式：

1. 添加“URL”动作。
2. 填入：

```text
a-shell://?command=cd%20~/Documents/txjx-zzc%20%26%26%20python3%20iOS_%E8%AF%8D%E5%BA%93%E5%90%88%E5%B9%B6.py
```

3. 添加“打开 URL”动作。
4. 保存。

如果脚本目录不是 `~/Documents/txjx-zzc`，需要修改命令里的路径，并做 URL encode。

## 重新配置

如果想换目录：

```sh
cd ~/Documents/txjx-zzc
pickFolder
root=$(pwd)
cd ~/Documents/txjx-zzc
python3 iOS_词库合并.py --reset-config --root "$root" --default-state
```

也可以删除：

```sh
rm ios_zzc_merge_config.json
```

再重新执行首次配置。

## 路径原则

iCloud 模式：

- 最终码表目录选 iCloud。
- `zzc_state` 默认在同一棵 iCloud 目录。
- 合并后元书重新部署/同步，把 iCloud 变化传回应用文件和键盘文件。

非 iCloud 模式：

- 最终码表目录选应用文件。
- `zzc_state` 默认在同一棵应用文件目录。
- 不碰 iCloud。

禁止：

- 码表在 iCloud，`zzc_state` 在 a-Shell 本地。
- 码表在应用文件，`zzc_state` 在 iCloud。
- 用脚本所在目录当数据目录。
