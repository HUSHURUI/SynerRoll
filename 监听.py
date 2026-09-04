import json
import time
import os
from typing import Any
from datetime import datetime

# ===================== 配置项 =====================
JSON_FILE_PATH = "server/data/projects.json"       # 你要监听的JSON
LOG_FILE_PATH = "json_change.log"  # 变化记录保存到这里
CHECK_INTERVAL = 0.5               # 检测间隔0.5秒
# ===================================================

def load_json(path: str) -> Any | None:
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except:
        return None

def get_modify_time(path: str) -> float:
    try:
        return os.path.getmtime(path)
    except:
        return 0

def diff_json(old: Any, new: Any, path: str = "") -> list[str]:
    changes = []

    # 类型不同
    if type(old) != type(new):
        changes.append(f"🟡 类型变化: {path} | {type(old).__name__} → {type(new).__name__}")
        return changes

    # 字典
    if isinstance(old, dict) and isinstance(new, dict):
        # 检查删除
        for k in old:
            full = f"{path}.{k}" if path else str(k)
            if k not in new:
                changes.append(f"🔴 删除: {full} = {repr(old[k])}")
            else:
                changes.extend(diff_json(old[k], new[k], full))
        # 检查新增/修改
        for k in new:
            full = f"{path}.{k}" if path else str(k)
            if k not in old:
                changes.append(f"🟢 新增: {full} = {repr(new[k])}")
        return changes

    # 列表/数组
    if isinstance(old, list) and isinstance(new, list):
        # 按索引对比
        max_len = max(len(old), len(new))
        for i in range(max_len):
            full = f"{path}[{i}]"
            if i >= len(old):
                changes.append(f"🟢 新增: {full} = {repr(new[i])}")
            elif i >= len(new):
                changes.append(f"🔴 删除: {full} = {repr(old[i])}")
            else:
                changes.extend(diff_json(old[i], new[i], full))
        return changes

    # 普通值
    if old != new:
        changes.append(f"🟡 修改: {path} | {repr(old)} → {repr(new)}")
    return changes

def write_log(line: str):
    try:
        with open(LOG_FILE_PATH, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass

def main():
    print("=" * 70)
    print("📡 JSON 超级监视器 - 支持复杂嵌套/对象/数组/任意结构")
    print(f"📂 监听: {JSON_FILE_PATH}")
    print(f"📝 日志: {LOG_FILE_PATH}")
    print(f"🔄 间隔: {CHECK_INTERVAL}s")
    print(f"⏱ 精度: 毫秒")
    print("=" * 70)
    print("💡 实时检测：新增 | 删除 | 修改 | 类型变化\n")

    last_mtime = get_modify_time(JSON_FILE_PATH)
    last_data = load_json(JSON_FILE_PATH)

    while True:
        time.sleep(CHECK_INTERVAL)
        current_mtime = get_modify_time(JSON_FILE_PATH)
        if current_mtime == last_mtime:
            continue

        now_str = datetime.now().strftime("%H:%M:%S.%f")[:-3]
        current_data = load_json(JSON_FILE_PATH)
        changes = diff_json(last_data, current_data)

        print(f"\n⏰ {now_str} 📌 文件已变化")
        write_log(f"[{now_str}] 文件已变化")

        if changes:
            for msg in changes:
                print(f"   {msg}")
                write_log(f"[{now_str}] {msg}")
        else:
            print("   ℹ️ 无有效变化")
            write_log(f"[{now_str}] 无有效变化")

        last_mtime = current_mtime
        last_data = current_data

if __name__ == "__main__":
    main()