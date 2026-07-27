import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ICON = os.path.join(HERE, "icon.png")

# apply.ps1 writes the btop4win.exe path here.
with open(os.path.join(HERE, "btoppath.txt"), encoding="utf-8-sig") as f:
    BTOP = f.read().strip()


def query():
    return {
        "result": [
            {
                "Title": "btop",
                "SubTitle": "System monitor",
                "IcoPath": ICON,
                "JsonRPCAction": {"method": "run", "parameters": [], "dontHideAfterAction": False},
            }
        ]
    }


def run():
    # Launching the exe directly skips the shell profile and fastfetch.
    DETACHED_PROCESS, NEW_GROUP = 0x8, 0x200
    subprocess.Popen(
        ["wt.exe", "-w", "new", BTOP],
        creationflags=DETACHED_PROCESS | NEW_GROUP,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        close_fds=True,
    )
    return {}


req = json.loads(sys.argv[1])
if req["method"] == "query":
    out = query()
elif req["method"] == "run":
    out = run()
else:
    out = {}
print(json.dumps(out))
