# scoping/listup.py

import subprocess
import yaml
from pathlib import Path

def get_allowed_extensions() -> list[str]:
    """user_config.yml에서 확장자 목록 로딩"""
    config_path = Path("config/user_config.yml")
    if not config_path.exists():
        return [".py", ".sh", ".html", ".css", ".js", ".ts"]
    
    with config_path.open(encoding="utf-8") as f:
        cfg = yaml.safe_load(f)
    return cfg.get("change detection", {}).get("provuuider", [])

def get_changed_files() -> list[str]:
    """
    Git에서 변경된 파일 리스트업
    - tracked 상태만
    - 상태: Modified, Added
    - 숨김폴더, 캐시폴더, 삭제파일 제외
    - 지정 확장자만 허용
    """
    allowed_exts = set(get_allowed_extensions())
    ignored_dirs = {
        "__pycache__", ".ipynb_checkpoints", ".mypy_cache",
        ".pytest_cache", "build", "dist", "venv", ".git"
    }

    result = subprocess.run(["git", "status", "--porcelain=v2"],
                            capture_output=True, text=True)
    if result.returncode != 0:
        print(f"❌ git status 실패: {result.stderr}")
        return []

    files = []
    for line in result.stdout.strip().splitlines():
        if not line.startswith("1 "):
            continue  # untracked, rename 등 제외
        parts = line.strip().split(" ")
        xy = parts[1]
        filepath = parts[-1]

        # 상태 체크
        if "M" not in xy and "A" not in xy:
            continue

        p = Path(filepath)
        if not p.exists():
            continue
        if p.suffix not in allowed_exts:
            continue
        if any(part.startswith(".") or part in ignored_dirs for part in p.parts):
            continue

        files.append(filepath)

    return files
