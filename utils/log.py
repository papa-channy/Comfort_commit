# utils/log.py

import yaml
import json
from pathlib import Path
import datetime

CONFIG_PATH = Path("config/user_config.yml")
DEFAULT_LOG_PATH = Path("log/llm_call.jsonl")

def is_debug_mode() -> bool:
    try:
        with CONFIG_PATH.open(encoding="utf-8") as f:
            cfg = yaml.safe_load(f)
        return cfg.get("debug mode", "off").lower() == "on"
    except Exception:
        return False

def log(message: str, level: str = "INFO", source: str = "llm_router", log_path: Path = DEFAULT_LOG_PATH):
    """
    JSONL 로그 기록
    - message: 로그 메시지
    - level: 로그 레벨 ("INFO", "WARN", "ERROR")
    - source: 어떤 모듈에서 발생한 로그인지 표시
    - log_path: 저장 경로 (기본 log/llm_call.jsonl)
    """
    timestamp = datetime.datetime.now().isoformat()
    record = {
        "timestamp": timestamp,
        "level": level.upper(),
        "message": message,
        "source": source
    }

    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(record, ensure_ascii=False) + "\n")

    if is_debug_mode():
        print(json.dumps(record, ensure_ascii=False))
