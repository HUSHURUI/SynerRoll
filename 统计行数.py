"""
代码行数统计工具
- 通过 git ls-files 自动排除 .gitignore 忽略的文件
- 排除 .json 等配置文件
- 按前端/后端分别统计
"""

import os
import subprocess
import sys
from collections import defaultdict

# Windows 终端 UTF-8 支持
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")

# 要统计的文件扩展名（排除 .json 等配置文件）
FRONTEND_EXTENSIONS = {
    ".vue", ".ts", ".js", ".tsx", ".jsx",
    ".css", ".scss", ".less", ".html",
}

BACKEND_EXTENSIONS = {
    ".jl",  # Julia
}

ALL_EXTENSIONS = FRONTEND_EXTENSIONS | BACKEND_EXTENSIONS

# 前端目录（Nuxt 项目）
FRONTEND_DIRS = {
    "app", "assets", "composables", "config",
    "server", "state", "templates", "types", "utils", "public",
}

# 后端目录
BACKEND_DIRS = {"backend"}


def get_tracked_files(root_dir: str) -> list[str]:
    """通过 git ls-files 获取所有被 Git 跟踪的文件（自动排除 .gitignore）"""
    result = subprocess.run(
        ["git", "ls-files"],
        cwd=root_dir,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print("⚠️  git 命令执行失败，回退到 os.walk 模式")
        return None
    return [os.path.normpath(f) for f in result.stdout.strip().splitlines() if f]


def count_lines(file_path: str) -> int:
    """统计单个文件的有效代码行数（非空行）"""
    for enc in ("utf-8", "gbk", "latin-1"):
        try:
            with open(file_path, "r", encoding=enc) as f:
                return sum(1 for line in f if line.strip())
        except (UnicodeDecodeError, UnicodeError):
            continue
    return 0


def classify_file(rel_path: str) -> str | None:
    """判断文件属于前端还是后端"""
    top_dir = rel_path.split(os.sep)[0]
    if top_dir in FRONTEND_DIRS:
        return "frontend"
    if top_dir in BACKEND_DIRS:
        return "backend"
    # 根目录文件（如 nuxt.config.ts）算前端
    if os.sep not in rel_path:
        return "frontend"
    return None


def format_table(title: str, stats: dict[str, int], total_lines: int, total_files: int):
    """格式化输出统计表格"""
    print(f"  {title}")
    print(f"  文件数: {total_files} 个")
    print(f"  总行数: {total_lines:,} 行")
    print(f"{'-' * 50}")
    for ext, count in sorted(stats.items(), key=lambda x: -x[1]):
        pct = count / total_lines * 100 if total_lines else 0
        
        print(f"  {ext:6}  {count:>8,} 行  ({pct:5.1f}%)")
    print(f"{'=' * 50}")


def main():
    root_dir = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()
    print(f"📁 统计目录: {root_dir}\n")

    files = get_tracked_files(root_dir)

    if files is None:
        # git 不可用时回退
        print("回退模式：仅统计代码文件，无法自动排除 .gitignore")
        return

    # 分类统计
    fe_stats, be_stats = defaultdict(int), defaultdict(int)
    fe_files, be_files = 0, 0
    fe_lines, be_lines = 0, 0

    for rel_path in files:
        ext = os.path.splitext(rel_path)[1].lower()
        if ext not in ALL_EXTENSIONS:
            continue

        category = classify_file(rel_path)
        if category is None:
            continue

        abs_path = os.path.join(root_dir, rel_path)
        if not os.path.isfile(abs_path):
            continue

        lines = count_lines(abs_path)

        if category == "frontend":
            fe_stats[ext] += lines
            fe_files += 1
            fe_lines += lines
        else:
            be_stats[ext] += lines
            be_files += 1
            be_lines += lines

    # 输出结果
    total_lines = fe_lines + be_lines
    total_files = fe_files + be_files

    print(f"🔥 核心代码总量: {total_lines:,} 行 ({total_files} 个文件)")

    format_table("🌐 前端代码 (Vue / TypeScript / CSS)", fe_stats, fe_lines, fe_files)
    format_table("⚙️  后端代码 (Julia)", be_stats, be_lines, be_files)


if __name__ == "__main__":
    main()
