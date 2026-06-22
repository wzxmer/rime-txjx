天行键 zzc 脚本说明

一、普通用户怎么用

Windows 用户：
1. 双击 Win_词库合并.exe
2. 如果需要撤回上一次合并，双击 Win_撤回合并.exe
3. Windows 只提供 exe，普通用户不需要 Python。

Mac 用户：
1. 当前提供源码脚本：
   - Mac_词库合并.py
   - Mac_撤回合并.py
2. 如果要做成不依赖 Python 的 Mac 可执行程序，请在 Mac 电脑上用 PyInstaller 或其他打包工具处理这两个 py 文件。

Linux 用户：
1. 运行 Linux_词库合并.py
2. 如果需要撤回上一次合并，运行 Linux_撤回合并.py
3. 需要电脑已安装 Python 3。

二、Mac 打包说明

把整个 zzc 目录放到 Mac 上，进入 zzc 目录后执行：

python3 -m pip install pyinstaller
python3 -m PyInstaller --onefile --name "Mac_词库合并" "Mac_词库合并.py"
python3 -m PyInstaller --onefile --name "Mac_撤回合并" "Mac_撤回合并.py"

打包完成后，可执行文件在：

dist/Mac_词库合并
dist/Mac_撤回合并

把这两个文件复制回 zzc 目录。

打包后把这两个无扩展可执行文件放回 zzc 目录：

Mac_词库合并
Mac_撤回合并

三、重要文件

../txjx.zzc.dict.yaml
- 自造词操作记录，也是临时 zzc 码表。

char_parts.tsv
- 单字拆分索引。
- 合并脚本会自动重建。

runtime_exact.tsv / index.tsv / group_*.tsv
- 输入法运行时快照。
- 合并后会清空重建。

撤回合并/
- 合并前自动备份目录。
- 只保留最近 3 份。

四、撤回合并规则

每次合并前，脚本会备份：
1. 正式码表
2. 当前 zzc 增量文件
3. manifest.txt

撤回脚本会显示最近 3 份备份，让用户手动选择恢复哪一份。

撤回是整文件恢复，不做复杂 diff。
这比从正式码表里逆向删除更可靠。

五、脚本入口说明

普通用户只运行对应平台名称开头的脚本或程序：
- Win_词库合并.exe / Win_撤回合并.exe
- Mac_词库合并.py / Mac_撤回合并.py
- Linux_词库合并.py / Linux_撤回合并.py
