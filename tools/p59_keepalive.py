#!/usr/bin/env python3
"""P59: keep device unlocked during test runs (wakeup + swipe every 45s in background thread)."""
import sys, time, threading
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import sh

_stop = threading.Event()


def keepalive():
    while not _stop.is_set():
        try:
            sh('power-shell setmode 602')
            sh('power-shell wakeup')
            sh('uinput -T -m 300 1250 300 200 400')
            time.sleep(2)
            sh('uinput -T -c 640 646')
        except Exception:
            pass
        _stop.wait(45)


def start():
    t = threading.Thread(target=keepalive, daemon=True)
    t.start()
    return t


def stop():
    _stop.set()


if __name__ == '__main__':
    start()
    time.sleep(5)
    print('keepalive running, screen should be awake')
    stop()
