# LLM/llm_decorator.py

from time import perf_counter
from utils.log import log

def llm_track(func):
    """
    LLMManager.call() 또는 기타 LLM 호출 함수에 데코레이터 적용
    호출 시간 측정 + 로그 기록 자동화
    """
    def wrapper(self, prompt: str, tag: str):
        start = perf_counter()
        try:
            result = func(self, prompt, tag)
            return result
        except Exception as e:
            log(
                message=f"[{self.stage}] 호출 실패 [{tag}] → {e}",
                level="ERROR",
                source="llm_manager"
            )
            raise
        finally:
            elapsed = round(perf_counter() - start, 3)
            log(
                message=f"[{self.stage}] 호출 완료 [{tag}] (⏱️ {elapsed}s)",
                level="INFO",
                source="llm_manager"
            )
    return wrapper
