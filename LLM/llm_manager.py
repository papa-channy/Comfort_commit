# llm_manager.py

from pathlib import Path
import json
import pandas as pd
from concurrent.futures import ThreadPoolExecutor, as_completed

from LLM.llm_router import call_llm
from LLM.llm_decorator import llm_track
from utils.log import log
from utils.path import get_timestamp
def choose_llm(user_uuid, requested_model):
    try:
        return call_llm_with_fireworks(model=requested_model)
    except FireworksLimitError:
        return call_llm_with_openrouter(model="gpt-4o-mini")

class LLMManager:
    def __init__(self, stage: str, df_for_call: pd.DataFrame):
        """
        stage: 'describe' or 'mk_msg'
        df_for_call: temp/{stage}.pkl에서 로드한 DataFrame
        """
        self.stage = stage
        self.df_for_call = df_for_call
        self.config = self._get_config()
        self.model = self.config["model"][0]
        self.provuuider = self.config["provuuider"][0]
        self.timestamp = get_timestamp()
        self.max_workers = self.config.get("parallel calls", 3)  # 기본 3개

    def _get_config(self) -> dict:
        config_path = Path("config/conf.json")
        with config_path.open(encoding="utf-8") as f:
            conf = json.load(f)
        return conf[self.stage]

    def call(self, prompt: str, tag: str) -> str:
        return self._call_model(prompt, tag)

    @llm_track
    def _call_model(self, prompt: str, tag: str) -> str:
        return call_llm(prompt, self.config)

    def call_all(self, prompts: list[str], tags: list[str]) -> list[str]:
        """
        병렬 LLM 호출
        - prompts: 프롬프트 문자열 리스트
        - tags: 각 프롬프트에 대한 고유 태그
        - conf.json 내 parallel calls 값에 따라 병렬 수 결정
        """
        results = [None] * len(prompts)
        with ThreadPoolExecutor(max_workers=self.max_workers) as executor:
            futures = {
                executor.submit(self.call, p, t): i
                for i, (p, t) in enumerate(zip(prompts, tags))
            }
            for future in as_completed(futures):
                uuidx = futures[future]
                try:
                    results[uuidx] = future.result()
                except Exception as e:
                    results[uuidx] = f"[ERROR] {e}"
        return results
