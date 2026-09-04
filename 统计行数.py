import os
import sys

# 要统计的文件类型
TARGET_EXTENSIONS = {
    ".vue", ".ts", ".js", ".tsx", ".jsx",
    ".css", ".scss", ".less", ".html", ".json"
}

# 要忽略的文件夹（前端项目通用）
IGNORE_DIRS = {
    "node_modules", "dist", "build", "output",
    ".nuxt", ".output", ".git", ".vscode",
    "coverage", "logs", "tmp", "cache"
}

def count_lines(directory: str):
    total_files = 0
    total_lines = 0
    file_type_stats = {ext: 0 for ext in TARGET_EXTENSIONS}

    for root, dirs, files in os.walk(directory):
        # 跳过忽略目录
        dirs[:] = [d for d in dirs if d not in IGNORE_DIRS]

        for file in files:
            ext = os.path.splitext(file)[1].lower()
            if ext not in TARGET_EXTENSIONS:
                continue

            file_path = os.path.join(root, file)
            try:
                with open(file_path, "r", encoding="utf-8") as f:
                    lines = f.readlines()
            except:
                try:
                    with open(file_path, "r", encoding="gbk") as f:
                        lines = f.readlines()
                except:
                    print(f"⚠️  无法读取: {file_path}")
                    continue

            line_count = len([l for l in lines if l.strip() != ""])  # 只算非空行
            total_lines += line_count
            total_files += 1
            file_type_stats[ext] += line_count

    return total_files, total_lines, file_type_stats

def main():
    target_dir = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()
    print(f"📁 正在统计目录: {target_dir}\n")

    total_files, total_lines, stats = count_lines(target_dir)

    print("=" * 50)
    print("📊 前端项目代码行数统计结果")
    print("=" * 50)
    print(f"✅ 统计文件总数: {total_files} 个")
    print(f"🔥 有效代码总行数: {total_lines:,} 行\n")

    print("📄 各类型代码行数：")
    for ext, count in stats.items():
        if count > 0:
            print(f"  {ext:6} → {count:,} 行")

    print("=" * 50)

if __name__ == "__main__":
    main()