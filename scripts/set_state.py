import sys
import os
import json
import time

STATE_FILE = os.path.expanduser("~/.desktop-pet/live_state.json")

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
elif target_state in ("stop", "idle"):
    target_state = "idle"

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
    conversations[convo_id] = "idle"
    conversation_times[convo_id] = now

# Prune stale conversations: working > 2 min (e.g. cancelled/killed), question > 5 min, idle > 3 min
cleaned_conversations = {}
cleaned_times = {}
for cid, st in conversations.items():
    last_seen = conversation_times.get(cid, now)
    if st == "working" and (now - last_seen > 120):
        continue
    if st == "question" and (now - last_seen > 300):
        continue
    if st == "idle" and (now - last_seen > 180):
        continue
    cleaned_conversations[cid] = st
    cleaned_times[cid] = last_seen

conversations = cleaned_conversations
conversation_times = cleaned_times

# Determine overall state by priority:
# Priority 1: question (if ANY conversation needs input / is awaiting user response)
# Priority 2: working (if ANY conversation is actively working)
# Priority 3: idle (all finished)
overall_state = "idle"
waiting_convo_id = None

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
tmp_file = f"{STATE_FILE}.{os.getpid()}_{time.time_ns()}.tmp"
try:
    with open(tmp_file, "w") as fp:
        json.dump(output_data, fp)
    os.replace(tmp_file, STATE_FILE)
except Exception:
    if os.path.exists(tmp_file):
        try:
            os.remove(tmp_file)
        except Exception:
            pass

# Required stdout contract:
if len(sys.argv) > 1 and sys.argv[1] == "pre_tool":
    print(json.dumps({"decision": "allow"}))
else:
    print(json.dumps({}))
