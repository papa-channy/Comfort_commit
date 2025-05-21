import os
import requests
from dotenv import load_dotenv
from pathlib import Path
from datetime import datetime

# 🔹 .env 로드 (.env는 git_auto 루트에 위치)
env_path = Path(__file__).parent.parent / ".env"
if env_path.exists():
    load_dotenv(dotenv_path=env_path)

WEBHOOK_URL = os.getenv("DISCORD_WEBHOOK_URL")

# 🔹 공통 Header
HEADERS = {
    "Content-Type": "application/json",
    "User-Agent": "DiscordBot (https://github.com/git-auto-bot, 1.0)"
}

# 🔹 ping(): Webhook이 살아있는지 확인용 메시지
def ping() -> bool:
    if not WEBHOOK_URL:
        return False
    try:
        payload = {
            "content": "✅ [Ping 테스트] Discord Webhook 연결 성공"
        }
        resp = requests.post(WEBHOOK_URL, headers=HEADERS, json=payload, timeout=5)
        return resp.status_code in [200, 204]
    except Exception as e:
        return False

# 🔹 send(): 커밋 결과 메시지 전송
def send(commit_msg: str, status: str = "success") -> bool:
    if not WEBHOOK_URL:
        return False

    prefix = "✅ Git Push 성공" if status == "success" else "❌ Git Push 실패"
    time_str = datetime.now().strftime("%Y-%m-%d %H:%M")

    body = f"""**{prefix}**
🕒 {time_str}
📝 **Commit Message**
{commit_msg}
"""
    try:
        resp = requests.post(WEBHOOK_URL, headers=HEADERS, json={"content": body}, timeout=10)
        return resp.status_code in [200, 204]
    except Exception as e:
        return False