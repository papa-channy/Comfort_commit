from pathlib import Path
import subprocess
from typing import Callable

def get_file_path(file: str, strategy_df, log_func: Callable | None = None) -> Path | None:
    """
    파일 이름과 전략 DataFrame을 기반으로 안전한 경로 반환
    - 전략 정보 없으면 None 반환
    """
    from scripts.ext_info import to_safe_filename

    row = strategy_df[strategy_df["File"] == file]
    if row.empty:
        if log_func:
            log_func(f"⚠️ 경로 조회 실패: {file} → strategy_df에 없음")
        return None
    return Path(row["path"].iloc[0]) / to_safe_filename(file)

def do_git_commit(filepath: Path, msg: str, log_func: Callable) -> bool:
    """
    파일 단위 Git 커밋 및 푸시 수행
    - 실패 시 False 반환 + 로그 기록
    """
    try:
        subprocess.run(["git", "add", str(filepath)], check=True)
        subprocess.run(["git", "commit", "-m", msg], check=True)
        subprocess.run(["git", "push"], check=True)
        return True
    except subprocess.CalledProcessError as e:
        log_func(f"❌ Git 커밋 실패: {filepath} → {e}")
        return False
    except Exception as e:
        log_func(f"❌ Git 예외 발생: {filepath} → {e}")
        return False

def send_notification(platforms: list[str], msg: str, log_func: Callable) -> list[str]:
    """
    지정된 플랫폼 리스트에 알림 메시지 전송
    - 실패 시 로그 기록
    - 유효하지 않은 플랫폼 필터링 처리
    - 실패한 플랫폼 리스트 반환
    """
    from notify import discord, gmail, kakao, slack


    failed = []

    for pf in platforms:
        sender = platform_map.get(pf)
        if not sender:
            log_func(f"[알림 실패] 알 수 없는 플랫폼: {pf}")
            failed.append(pf)
            continue

        try:
            sender(msg)
        except Exception as e:
            log_func(f"[알림 실패] {pf}: {e}")
            failed.append(pf)

    return failed

