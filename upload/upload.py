import os
import requests
import random
from datetime import datetime
from dotenv import load_dotenv
from pathlib import Path

# 내부 로깅 시스템이 있다면 연동
try:
    from config.setting import cfg
except ImportError:
    cfg = None

load_dotenv()

NOTION_TOKEN = os.getenv("NOTION_API_KEY")
NOTION_PAGE_uuid = os.getenv("NOTION_PAGE_uuid")

NOTION_URL_BASE = "https://api.notion.com/v1"
HEADERS = {
    "Authorization": f"Bearer {NOTION_TOKEN}",
    "Content-Type": "application/json",
    "Notion-Version": "2022-06-28"
}

COLORS = [
    "gray_background", "brown_background", "orange_background",
    "yellow_background", "green_background", "blue_background",
    "purple_background", "pink_background"
]

def get_repo_name() -> str:
    import subprocess
    try:
        url = subprocess.run(
            ["git", "config", "--get", "remote.origin.url"],
            capture_output=True, text=True, shell=True
        ).stdout.strip()
        repo = url.rstrip(".git").split("/")[-1] if url else "Unknown"
        return repo.replace("-", " ").title()
    except Exception:
        return "Unknown Repo"

def find_or_create_toggle_block(parent_uuid: str, title_text: str) -> str:
    try:
        children = get_notion_blocks(parent_uuid)
        for block in children:
            if block.get("type") != "toggle":
                continue
            rich_texts = block.get("toggle", {}).get("rich_text", [])
            if rich_texts and rich_texts[0]["text"]["content"] == title_text:
                return block["uuid"]
    except Exception:
        pass  # fallback to creation

    payload = {
        "children": [{
            "object": "block",
            "type": "toggle",
            "toggle": {
                "rich_text": [{"type": "text", "text": {"content": title_text}}],
                "children": []
            }
        }]
    }

    resp = requests.patch(
        f"{NOTION_URL_BASE}/blocks/{parent_uuid}/children",
        headers=HEADERS,
        json=payload
    )
    resp.raise_for_status()
    return resp.json()["results"][0]["uuid"]

def create_paragraph_block(title: str, text: str) -> dict:
    full_text = f"{title}\n\n{text}" if title else text
    return {
        "object": "block",
        "type": "paragraph",
        "paragraph": {
            "rich_text": [{
                "type": "text",
                "text": { "content": full_text }
            }],
            "color": random.choice(COLORS)
        }
    }

def upload_fx_record(filename: str, fx_text: str):
    now = datetime.now()
    repo_name = get_repo_name()
    top_toggle = f"📁 {repo_name}"
    muuid_toggle = f"📅 {now.strftime('%y년 %m월')}"
    time_toggle = f"🕒 {now.strftime('%d일 %p %I시 %M분').replace('AM', '오전').replace('PM', '오후')}"

    try:
        top_uuid = find_or_create_toggle_block(NOTION_PAGE_uuid, top_toggle)
        muuid_uuid = find_or_create_toggle_block(top_uuid, muuid_toggle)
        time_uuid = find_or_create_toggle_block(muuid_uuid, time_toggle)

        blocks = [create_paragraph_block(f"📘 FILE: {filename}", fx_text)]

        requests.patch(
            f"{NOTION_URL_BASE}/blocks/{time_uuid}/children",
            headers=HEADERS,
            json={"children": blocks}
        )
    except Exception as e:
        msg = f"[NOTION] ❌ {filename} 업로드 실패: {e}"
        if cfg and hasattr(cfg, "log"):
            cfg.log(msg, Path("logs/notion_fallback.log"))
        else:
            print(msg)

# ✅ 향후 확장용: 여러 파일 한 번에 업로드
def upload_fx_batch(file_text_pairs: list[tuple[str, str]]):
    now = datetime.now()
    repo_name = get_repo_name()
    top_toggle = f"📁 {repo_name}"
    muuid_toggle = f"📅 {now.strftime('%y년 %m월')}"
    time_toggle = f"🕒 {now.strftime('%d일 %p %I시 %M분').replace('AM', '오전').replace('PM', '오후')}"

    try:
        top_uuid = find_or_create_toggle_block(NOTION_PAGE_uuid, top_toggle)
        muuid_uuid = find_or_create_toggle_block(top_uuid, muuid_toggle)
        time_uuid = find_or_create_toggle_block(muuid_uuid, time_toggle)

        blocks = [
            create_paragraph_block(f"📘 FILE: {fn}", txt)
            for fn, txt in file_text_pairs
        ]

        requests.patch(
            f"{NOTION_URL_BASE}/blocks/{time_uuid}/children",
            headers=HEADERS,
            json={"children": blocks}
        )
    except Exception as e:
        msg = f"[NOTION] ❌ batch 업로드 실패: {e}"
        if cfg and hasattr(cfg, "log"):
            cfg.log(msg, Path("logs/notion_fallback.log"))
        else:
            print(msg)
