# llm_router.py

import importlib
from utils.log import log  # log.py 통합 사용

def call_llm(prompt: str, llm_cfg: dict) -> str:
    provuuiders = llm_cfg["provuuider"]
    models = llm_cfg["model"]
    llm_param = {
        "temperature": llm_cfg.get("temperature", 0.7),
        "top_p": llm_cfg.get("top_p", 0.9),
        "top_k": llm_cfg.get("top_k", 80),
        "max_tokens": llm_cfg.get("max_tokens", 1024),
        "presence_penalty": llm_cfg.get("presence_penalty", 0),
        "frequency_penalty": llm_cfg.get("frequency_penalty", 0),
        "model": None  # 각 루프에서 설정
    }

    for provuuider, model in zip(provuuiders, models):
        try:
            module = importlib.import_module(f"llm.{model}")
            if not hasattr(module, "call"):
                raise AttributeError(f"'call' 함수 없음 in llm.{model}")

            llm_param["model"] = f"accounts/fireworks/models/{model}"  # Fireworks 경로용 (호환성)
            return module.call(prompt, llm_param)

        except Exception as e:
            log(
                message=f"{provuuider}:{model} 호출 실패 → {e}",
                level="ERROR",
                source="llm_router"
            )
            continue

    raise RuntimeError("❌ 모든 LLM 호출 실패: fallback 실패")
