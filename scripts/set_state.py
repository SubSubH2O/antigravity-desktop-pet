import sys
import os
import json
import time

STATE_FILE = os.path.expanduser("~/.desktop-pet/live_state.json")
TMP_FILE = STATE_FILE + ".tmp"

target_state = sys.argv[1] if len(sys.argv) > 1 else "idle"

# Read hook payload from stdin if present
hook_payload = {}
try:
    if not sys.stdin.isatty():
        raw_input = sys.stdin.read().strip()
        if raw_input:
            hook_payload = json.loads(raw_input)
except Exception:
    pass

convo_id = hook_payload.get("conversationId", "default")
tool_name = hook_payload.get("toolCall", {}).get("name", "")

# Determine actual target state
if target_state == "pre_tool":
    if tool_name == "ask_question":
        target_state = "question"
    else:
        target_state = "working"
elif target_state == "post_tool_question":
    target_state = "working"

# Load existing state
existing_data = {
    "conversations": {},
    "conversation_times": {},
    "state": "idle",
    "waitingConversationId": None,
    "timestamp": int(time.time())
}

if os.path.exists(STATE_FILE):
    try:
        with open(STATE_FILE, "r") as fp:
            data = json.load(fp)
            if isinstance(data, dict):
                existing_data["conversations"] = data.get("conversations", {})
                existing_data["conversation_times"] = data.get("conversation_times", {})
    except Exception:
        pass

conversations = existing_data["conversations"]
conversation_times = existing_data["conversation_times"]
now = int(time.time())

if target_state in ("working", "question"):
    conversations[convo_id] = target_state
    conversation_times[convo_id] = now
elif target_state == "idle":
    if convo_id in conversations:
        conversations[convo_id] = "idle"
        conversation_times[convo_id] = now

# Prune conversations inactive for over 15 minutes or idle for over 3 minutes
cleaned_conversations = {}
cleaned_times = {}
for cid, st in conversations.items():
    last_seen = conversation_times.get(cid, now)
    if now - last_seen > 900:
        continue
    if st == "idle" and (now - last_seen > 180):
        continue
    cleaned_conversations[cid] = st
    cleaned_times[cid] = last_seen

conversations = cleaned_conversations
conversation_times = cleaned_times

# Determine overall state by priority:
# Priority 1: question (if ANY conversation needs input)
# Priority 2: working (if ANY conversation is working)
# Priority 3: idle (all finished)
overall_state = "idle"
waiting_convo_id = None

# Check for question first
for cid, st in conversations.items():
    if st == "question":
        overall_state = "question"
        waiting_convo_id = cid
        break

if overall_state != "question":
    for cid, st in conversations.items():
        if st == "working":
            overall_state = "working"
            break

output_data = {
    "state": overall_state,
    "waitingConversationId": waiting_convo_id,
    "conversations": conversations,
    "conversation_times": conversation_times,
    "timestamp": now
}

os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
with open(TMP_FILE, "w") as fp:
    json.dump(output_data, fp)
os.replace(TMP_FILE, STATE_FILE)

# Required stdout contract:
# PreToolUse requires {"decision": "allow"}
# PreInvocation, PostToolUse, and Stop require {}
if len(sys.argv) > 1 and sys.argv[1] == "pre_tool":
    print(json.dumps({"decision": "allow"}))
else:
    print(json.dumps({}))
