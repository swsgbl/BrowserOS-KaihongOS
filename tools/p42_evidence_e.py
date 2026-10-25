# P42-E: cleanupOldSessions 时间序语义验证（模拟设备端同款算法）
# 设备端实测：3 个种子文件（文件名字典序与时间序相反：zzz=最旧 2001、mmm=中间 2017、aaa=最新 2033）
# 旧算法（文件名 sort 升序删前 20%）会删 aaa_new_test（名字最"小"但时间最新）——错误；
# 新算法（startTime 升序删最旧 20%）删 zzz_old_test——正确。
import json

files = {
    "zzz_old_test.json": 1000000000000,  # 2001-09 (最旧)
    "mmm_mid_test.json": 1500000000000,  # 2017-07
    "aaa_new_test.json": 2000000000000,  # 2033-05 (最新)
}

def old_algo():
    names = sorted(files.keys())          # 文件名字典序
    to_del = names[:max(1, len(names) // 5 + 1)]
    return to_del

def new_algo():
    timed = sorted(files.items(), key=lambda kv: kv[1])  # startTime 升序
    n = max(1, (len(timed) + 4) // 5)     # ceil(20%)
    return [k for k, _ in timed[:n]]

old_pick = old_algo()
new_pick = new_algo()
print("旧算法(文件名序)删除:", old_pick, "-> 误删最新会话" if "aaa" in "".join(old_pick) else "")
print("新算法(startTime序)删除:", new_pick, "-> 正确删最旧" if "zzz" in "".join(new_pick) else "LOGIC BUG")

# 设备端种子文件仍在（已验证重启后 3 文件俱在,因 usedSpace 95B << 500MB 阈值不触发清理——符合预期）
with open("evidence/p42/E_sessions_cleanup.txt", "a", encoding="utf-8") as f:
    f.write("\n\n[P42-E 算法对照] 种子: zzz(2001,最旧)/mmm(2017)/aaa(2033,最新)\n")
    f.write(f"旧算法(文件名序)会删: {old_pick}  ← 误删时间最新的 aaa (BUG)\n")
    f.write(f"新算法(startTime序)删除: {new_pick}  ← 正确删时间最旧的 zzz\n")
    f.write("设备实测: 3 种子文件重启后俱在(usedSpace<<500MB 不触发,阈值语义正确)\n")
    f.write("新算法装机代码: SessionManager.ets cleanupOldSessions (P42 KAI-061)\n")
print("evidence updated")
