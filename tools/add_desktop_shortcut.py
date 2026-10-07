"""P8: Pin BrowserOS to the KaihongOS desktop + dock, deterministically.

Device facts (hmh, 2026-10-07, from live DesktopItem.db / AppDockTable.db dumps):
  DesktopItem(id TEXT PK, x, y, xPosition, yPosition, type=1, title, size,
              createTime, modifyTime, filePath, bundleName, abilityName)
  AppDockTable(bundleName TEXT PK, orderIndex INTEGER)
  .app descriptor files live in /storage/cloud/100/files/Docs/Desktop/ (device path),
    each named <bundleName>.app and containing a JSON descriptor (see below).
  Grid: column x -> xPosition = 16 + 106*x ; row y -> yPosition = 16 + 126*y
    (verified against pre-existing rows: files.app y=1@142, browser y=3@394...)

This script:
  1. writes the .app descriptor to the device Docs/Desktop dir
  2. pulls both DBs, inserts/updates the BrowserOS row at x=0,y=6 (16,772),
     dock orderIndex = max+1, checkpoints WAL, pushes back atomically:
     force-stop launcher -> rm -wal/-shm -> cp -> chown 20010015:20010015 -> chmod 660
"""
import json, os, subprocess, sqlite3, shutil, sys, time

HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
TARGET = "127.0.0.1:15566"
BUNDLE = "com.browseros.kaihong"
ABILITY = "EntryAbility"
LABEL = "BrowserOS"
DEVICE_DESKTOP = "/storage/cloud/100/files/Docs/Desktop"
APP_FILE = DEVICE_DESKTOP + "/" + BUNDLE + ".app"
DB_DIR = "/data/app/el1/100/database/com.ohos.launcher/entry/rdb"
DESKTOP_DB = "DesktopItem.db"
DOCK_DB = "AppDockTable.db"
OWNER = "20010015:20010015"
WORK = os.path.join(os.path.dirname(__file__), "..", ".verify", "p8_shortcut")
X, Y = 0, 6
XPOS, YPOS = 16, 772

DESCRIPTOR = {
    "icon": APP_FILE,
    "label": LABEL,
    "bundleName": BUNDLE,
    "abilityName": ABILITY,
    "type": 1,
}


def hdc(*args, check=True, binary=False):
    r = subprocess.run([HDC, "-t", TARGET] + list(args), capture_output=True,
                       text=not binary)
    out = (r.stdout or "") + (r.stderr or "")
    if check and r.returncode != 0:
        raise RuntimeError("hdc %s failed: %s" % (args[:2], out[-300:]))
    return r.stdout if not binary else r.stdout


def main():
    os.makedirs(WORK, exist_ok=True)

    # -- 1. write .app descriptor --
    local_desc = os.path.join(WORK, "com.browseros.kaihong.app")
    with open(local_desc, "w", encoding="utf-8") as f:
        json.dump(DESCRIPTOR, f, ensure_ascii=False, indent=2)
    hdc("shell", "mkdir -p " + DEVICE_DESKTOP)
    hdc("file", "send", local_desc, APP_FILE)
    hdc("shell", "chown %s %s" % (OWNER, APP_FILE))
    hdc("shell", "chmod 660 %s" % APP_FILE)
    print("[1] descriptor written:", APP_FILE)

    # -- 2. pull DBs (with wal/shm if present) --
    for db in [DESKTOP_DB, DOCK_DB]:
        for suffix in ["", "-wal", "-shm"]:
            try:
                hdc("file", "recv", "%s/%s%s" % (DB_DIR, db, suffix),
                    os.path.join(WORK, db + suffix), check=False)
            except Exception:
                pass
    print("[2] DBs pulled to", WORK)

    def patch(db, table, sql_fn, desc):
        p = os.path.join(WORK, db)
        con = sqlite3.connect(p)
        cur = con.cursor()
        cur.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        cur.close()
        sql_fn(con)
        con.commit()
        cur = con.cursor()
        cur.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        cur.close()
        con.close()
        print("[3]", desc, "patched")

    def desktop_fn(con):
        row = con.execute("SELECT id FROM DesktopItem WHERE bundleName=?", (BUNDLE,)).fetchone()
        now = int(time.time())
        if row:
            con.execute("UPDATE DesktopItem SET x=?, y=?, xPosition=?, yPosition=?, title=?, "
                        "abilityName=?, modifyTime=? WHERE bundleName=?",
                        (X, Y, XPOS, YPOS, LABEL, ABILITY, now, BUNDLE))
        else:
            con.execute("INSERT INTO DesktopItem (id, x, y, xPosition, yPosition, type, title, "
                        "size, createTime, modifyTime, filePath, bundleName, abilityName) "
                        "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
                        ("file://docs/storage/Users/currentUser/Desktop/%s.app" % BUNDLE,
                         X, Y, XPOS, YPOS, 1, LABEL, 86, now, now, APP_FILE, BUNDLE, ABILITY))

    def dock_fn(con):
        row = con.execute("SELECT orderIndex FROM AppDockTable WHERE bundleName=?", (BUNDLE,)).fetchone()
        if row:
            print("    dock row exists @", row[0], "(keep)")
            return
        mx = con.execute("SELECT MAX(orderIndex) FROM AppDockTable").fetchone()[0] or 0
        con.execute("INSERT INTO AppDockTable (bundleName, orderIndex) VALUES (?, ?)",
                    (BUNDLE, int(mx) + 1))

    patch(DESKTOP_DB, "DesktopItem", desktop_fn, "DesktopItem x=0 y=6 (16,772)")
    patch(DOCK_DB, "AppDockTable", dock_fn, "AppDockTable max+1")

    # -- 3. atomic push sequence (single hdc shell) --
    seq = ("aa force-stop com.ohos.launcher; "
           "rm -f {d}/{a}-wal {d}/{a}-shm {d}/{b}-wal {d}/{b}-shm; "
           "cp /data/local/tmp/{a} {d}/{a}; cp /data/local/tmp/{b} {d}/{b}; "
           "chown {o} {d}/{a} {d}/{b}; chmod 660 {d}/{a} {d}/{b}"
           ).format(d=DB_DIR, a=DESKTOP_DB, b=DOCK_DB, o=OWNER)
    hdc("file", "send", os.path.join(WORK, DESKTOP_DB), "/data/local/tmp/" + DESKTOP_DB)
    hdc("file", "send", os.path.join(WORK, DOCK_DB), "/data/local/tmp/" + DOCK_DB)
    print("[4] pushing:", seq)
    hdc("shell", seq)
    print("[5] DONE - shortcut pinned. Launcher restarts on next boot or 'aa start'.")


if __name__ == "__main__":
    main()
