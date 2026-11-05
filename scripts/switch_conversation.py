#!/usr/bin/env python3
import sys
import os
import re
import subprocess
import urllib.request
import ssl
import json

if len(sys.argv) < 2:
    sys.exit(0)

target_convo_id = sys.argv[1].strip()
if not target_convo_id:
    sys.exit(0)

# 1. Discover LanguageServer port from main.log
log_path = os.path.expanduser("~/Library/Logs/Antigravity/main.log")
port = None
if os.path.exists(log_path):
    with open(log_path) as fp:
        for line in reversed(fp.readlines()):
            m = re.search(r'Local:\s+https?://127\.0\.0\.1:(\d+)', line)
            if m:
                port = m.group(1)
                break

# 2. Discover CSRF token from running process
csrf = None
try:
    ps_out = subprocess.check_output(['ps', '-A', '-o', 'command']).decode()
    m = re.search(r'--csrf_token\s+([a-f0-9-]+)', ps_out)
    if m:
        csrf = m.group(1)
except Exception:
    pass

if not port or not csrf:
    sys.exit(0)

url = f"https://127.0.0.1:{port}/exa.language_server_pb.LanguageServerService/SetBrowserOpenConversation"
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

req = urllib.request.Request(
    url,
    data=json.dumps({"conversationId": target_convo_id}).encode('utf-8'),
    headers={
        "Content-Type": "application/json",
        "x-codeium-csrf-token": csrf
    }
)
try:
    with urllib.request.urlopen(req, context=ctx, timeout=2) as resp:
        pass
except Exception:
    pass
