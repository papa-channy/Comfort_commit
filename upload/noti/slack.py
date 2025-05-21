import os
import requests
from dotenv import load_dotenv
from pathlib import Path
from datetime import datetime

# 🔹 .env 로드
env_path = Path(__file__).parent.parent / ".env"
if env_path.exists():
    load_dotenv(dotenv_path=env_path)

WEBHOOK_URL = os.getenv("SLACK_WEBHOOK_URL")

# 🔹 ping(): 슬랙 Webhook 테스트
def ping() -> bool:
    return send("✅ [Ping 테스트] Slack Webhook 연결 성공", "success")

# 🔹 send(): 커밋 메시지 전송
def send(commit_msg: str, status: str = "success") -> bool:
    if not WEBHOOK_URL:
        return False

    prefix = "✅ Git Push 성공" if status == "success" else "❌ Git Push 실패"
    time_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    text = f"*{prefix}*\n🕒 {time_str}\n\n```{commit_msg}```"

    try:
        resp = requests.post(WEBHOOK_URL, json={"text": text}, timeout=5)
        return resp.status_code == 200
    except:
        return False