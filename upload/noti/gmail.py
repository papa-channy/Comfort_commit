import os
import smtplib
from email.mime.text import MIMEText
from dotenv import load_dotenv
from pathlib import Path
from datetime import datetime

# 🔹 .env 로드
env_path = Path(__file__).parent.parent / ".env"
if env_path.exists():
    load_dotenv(dotenv_path=env_path)

GMAIL_USER = os.getenv("GMAIL_USER")
GMAIL_APP_PASSWORD = os.getenv("GMAIL_APP_PASSWORD")
TO_EMAIL = os.getenv("GMAIL_TO_EMAIL", GMAIL_USER)

# 🔹 ping(): 연결 테스트
def ping() -> bool:
    return send("✅ [Ping 테스트] Gmail SMTP 연결 성공", "success")

# 🔹 send(): 실제 커밋 메시지 전송
def send(commit_msg: str, status: str = "success") -> bool:
    try:
        prefix = "✅ Git Push 성공" if status == "success" else "❌ Git Push 실패"
        time_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        subject = f"[Git 알림] {prefix}"
        body = f"{prefix}\n🕒 {time_str}\n\n📝 Commit Message:\n{commit_msg}"

        msg = MIMEText(body)
        msg["Subject"] = subject
        msg["From"] = GMAIL_USER
        msg["To"] = TO_EMAIL

        with smtplib.SMTP_SSL("smtp.gmail.com", 465) as server:
            server.login(GMAIL_USER, GMAIL_APP_PASSWORD)
            server.send_message(msg)
        return True
    except:
        return False