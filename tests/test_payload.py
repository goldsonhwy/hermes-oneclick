#!/usr/bin/env python3
import base64, json, re

payload={"telegram_token":"123456789:"+"A"*35,"model":"demo-model","provider":"custom","base_url":"https://example.com/v1","api_key":"sk-demo"}
encoded=base64.b64encode(json.dumps(payload).encode()).decode()
decoded=json.loads(base64.b64decode(encoded))
assert decoded==payload
assert re.fullmatch(r"\d+:[A-Za-z0-9_-]{30,}",decoded["telegram_token"])
print("payload test: OK")
