import os
import json
import time
import requests
from pathlib import Path
from datetime import datetime
from dotenv import load_dotenv
# 🔹 환경변수 로드
load_dotenv(dotenv_path=Path(__file__).parent.parent / ".env")

CLIENT_uuid = os.getenv("KAKAO_CLIENT_uuid")
REFRESH_TOKEN = os.getenv("KAKAO_REFRESH_TOKEN")
TOKEN_PATH = Path("config/kakao.json").resolve()
API_URL = "https://kapi.kakao.com/v2/api/talk/memo/default/send"
TOKEN_URL = "https://kauth.kakao.com/oauth/token"

# 🔧 access_token 저장
def save_access_token(token: str):
    TOKEN_PATH.parent.mkdir(parents=True, exist_ok=True)
    data = {
        "access_token": token,
        "updated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    }
    TOKEN_PATH.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[KAKAO] ✅ access_token 저장됨: {TOKEN_PATH}")

# 🔧 access_token 로드
def load_access_token() -> str | None:
    if TOKEN_PATH.exists():
        data = json.loads(TOKEN_PATH.read_text(encoding="utf-8"))
        return data.get("access_token")
    return None

# 🔧 access_token 갱신
def refresh_access_token() -> str | None:
    if not CLIENT_uuid or not REFRESH_TOKEN:
        print("[KAKAO] ❌ 환경변수 CLIENT_uuid 또는 REFRESH_TOKEN 누락")
        return None

    data = {
        "grant_type": "refresh_token",
        "client_uuid": CLIENT_uuid,
        "refresh_token": REFRESH_TOKEN
    }

    try:
        print("[KAKAO] ▶ refresh 요청 payload:", data)
        print("[KAKAO] ▶ refresh 요청 URL:", TOKEN_URL)
        resp = requests.post(TOKEN_URL, data=data, timeout=5)
        print("[KAKAO] ▶ 응답 상태코드:", resp.status_code)
        print("[KAKAO] ▶ 응답 본문:", resp.text)
        resp.raise_for_status()
        new_token = resp.json().get("access_token")
        if new_token:
            if TOKEN_PATH.exists():
                TOKEN_PATH.unlink()
                print("[KAKAO] 🧹 이전 kakao.json 삭제 완료")
            save_access_token(new_token)
            time.sleep(5)
            return new_token
    except Exception as e:
        print(f"[KAKAO] ❌ 토큰 갱신 실패: {e}")
    return None

# 🔧 메시지 전송 요청
def send_kakao_message(token: str, message: str) -> bool:
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/x-www-form-urlencoded;charset=utf-8"
    }
    payload = {
        "object_type": "text",
        "text": message,
        "link": {
            "web_url": "https://github.com",
            "mobile_web_url": "https://github.com"
        }
    }
    try:
        resp = requests.post(
            API_URL,
            headers=headers,
            data={"template_object": json.dumps(payload, ensure_ascii=False)},
            timeout=5
        )
        if resp.status_code == 401:
            print("[KAKAO] ❗ access_token 만료로 인해 401 반환됨")
            return False
        return resp.status_code == 200 and resp.json().get("result_code") == 0
    except Exception as e:
        return False

# ✅ commit 메시지 전송
def send(commit_msg: str, status: str = "success") -> str:
    token = load_access_token()
    if not token:
        msg = "[KAKAO] ❌ access_token 없음 → 갱신 시도"
        refresh_token = refresh_access_token()
        if not refresh_token:
            return msg + "\n[KAKAO] ❌ 토큰 갱신 실패"
        token = refresh_token

    prefix = "✅ Git Push 성공" if status == "success" else "❌ Git Push 실패"
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    msg = f"{prefix}\n🕒 {timestamp}\n\n📝 Commit Message:\n{commit_msg}"

    if send_kakao_message(token, msg):
        return "[KAKAO] ✅ 메시지 전송 성공"

    # access_token 만료 → refresh 재시도
    refresh_token = refresh_access_token()
    if not refresh_token:
        return "[KAKAO] ❌ 토큰 갱신 실패"

    if send_kakao_message(refresh_token, msg):
        return "[KAKAO] ✅ 메시지 전송 성공 (토큰 갱신 후)"
    return "[KAKAO] ❌ 최종 전송 실패"

# ✅ Ping 테스트
def ping() -> bool:
    token = load_access_token()
    if not token:
        print("[KAKAO] ❌ ping 실패: access_token 없음")
        token = refresh_access_token()
        if not token:
            return False

    success = send_kakao_message(token, "✅ [Ping 테스트] 카카오 알림 연결 성공")
    if success:
        return True

    print("[KAKAO] 🔄 Ping 중 토큰 만료 추정 → 갱신 시도")
    token = refresh_access_token()
    if not token:
        return False
    return send_kakao_message(token, "✅ [Ping 테스트] 카카오 알림 연결 성공")
