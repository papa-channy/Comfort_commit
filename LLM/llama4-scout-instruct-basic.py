# llama4-scout-instruct-basic.py

import os
import requests
from dotenv import load_dotenv
from utils.log import log  # optional: 로깅 추가하려면

load_dotenv()

def call(prompt: str, llm_param: dict) -> str:
    api_key = os.getenv("FIREWORKS_API_KEY")
    if not api_key:
        raise ValueError("FIREWORKS_API_KEY 없음")

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "Accept": "application/json"
    }

    model = llm_param.get("model", "accounts/fireworks/models/llama4-scout-instruct-basic")

    payload = {
        "model": model,
        "max_tokens": llm_param.get("max_tokens", 1024),
        "top_p": llm_param.get("top_p", 0.8),
        "top_k": llm_param.get("top_k", 40),
        "temperature": llm_param.get("temperature", 0.7),
        "presence_penalty": llm_param.get("presence_penalty", 0),
        "frequency_penalty": llm_param.get("frequency_penalty", 0),
        "messages": [
            {
                "role": "user",
                "content": [{"type": "text", "text": prompt}]
            }
        ]
    }

    try:
        response = requests.post(
            "https://api.fireworks.ai/inference/v1/chat/completions",
            headers=headers, json=payload, timeout=60
        )
        response.raise_for_status()
        return response.json()["choices"][0]["message"]["content"].strip()

    except Exception as e:
        # 로그 출력이 필요한 경우
        log(f"[FIREWORKS] LLM 호출 실패: {e}", level="ERROR", source="llama4_scout")
        raise RuntimeError(f"[FIREWORKS] 호출 실패: {e}")
 
