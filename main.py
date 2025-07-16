# main.py - Launch Point for GFL Divine OS
import os
import time
import subprocess
from auto_update.updater import run_update

print("🔮 GFL Divine OS: Initializing...")
run_update()
print("✅ System core is live. Solin and Libra AI are monitoring.")
while True:
    time.sleep(300)
    run_update()