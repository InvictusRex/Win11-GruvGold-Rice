import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ICON = os.path.join(HERE, "icon.png")

# apply.ps1 writes the path of the installed exam-mode.ps1 here.
with open(os.path.join(HERE, "examscript.txt"), encoding="utf-8-sig") as f:
    SCRIPT = f.read().strip()

OPTIONS = {
    "on": ("Exam mode: ON", "Stop yasb, komorebi, whkd, masir, AutoHotkey, Rainmeter, Everything, Flow Launcher; disable autostart", []),
    "off": ("Exam mode: OFF", "Restore autostart and bring the rice back", ["-Off"]),
}


def query(search):
    search = search.strip().lower()
    return {
        "result": [
            {
                "Title": title,
                "SubTitle": sub,
                "IcoPath": ICON,
                "JsonRPCAction": {"method": "run", "parameters": [key], "dontHideAfterAction": False},
            }
            for key, (title, sub, _) in OPTIONS.items()
            if key.startswith(search)
        ]
    }


def run(key):
    # Exam mode kills Flow Launcher, which is this process's parent - own process
    # group so it survives. Not DETACHED_PROCESS: powershell.exe never runs under it.
    NEW_GROUP, NO_WINDOW = 0x200, 0x08000000
    subprocess.Popen(
        ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", SCRIPT, *OPTIONS[key][2]],
        creationflags=NEW_GROUP | NO_WINDOW,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        close_fds=True,
    )
    return {}


req = json.loads(sys.argv[1])
params = req.get("parameters", [])
if req["method"] == "query":
    out = query(params[0] if params else "")
elif req["method"] == "run" and params and params[0] in OPTIONS:
    out = run(params[0])
else:
    out = {}
print(json.dumps(out))
