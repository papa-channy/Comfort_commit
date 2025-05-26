import yaml
import id
import pandas as pd
from pathlib import Path
import tiktoken

from listup import get_changed_files
from import_flow import ImportAnalyzer
from extract_rel_fx import RelatedFunctionFinder

def load_debug_mode() -> bool:
    config_path = Path("config/user_config.yml")
    if not config_path.exists():
        return False
    with config_path.open(encoding="utf-8") as f:
        cfg = yaml.safe_load(f)
    return cfg.get("debug mode", "off").lower() == "on"

def get_token_count_gpt4o(file_path: Path) -> int:
    try:
        enc = tiktoken.encoding_for_model("gpt-4o")
        text = file_path.read_text(encoding="utf-8", errors="ignore")
        return len(enc.encode(text))
    except:
        return 0

def convert_to_group_df() -> pd.DataFrame:
    changed_files = get_changed_files()
    if not changed_files:
        print("❌ 변경된 파일 없음")
        return pd.DataFrame()

    analyzer = ImportAnalyzer()
    finder = RelatedFunctionFinder()
    debug = load_debug_mode()
    all_records = []

    for file_path in changed_files:
        file = Path(file_path)
        token_cnt = get_token_count_gpt4o(file)
        if token_cnt <= 5:
            if debug:
                print(f"⚠️ 토큰 수 {token_cnt} → 생략된 파일: {file}")
            continue

        imports = analyzer.analyze_file(file)
        rel_map = finder.analyze_file(file)

        if debug:
            print(f"\n📂 파일: {file}")
            print("📎 import하고 있는 파일:")
            if imports:
                for i in imports:
                    print(f"  → {i}")
            else:
                print("  (없음)")

            print("🔗 함수별로 참조된 외부 파일:")
            for fx, rels in rel_map.items():
                print(f"  🔸 {fx}() →")
                if rels:
                    for r in rels:
                        print(f"    - {r}")
                else:
                    print("    (없음)")

        record = {
            "file": str(file),
            "id": id.id4().hex[:8],
            "token_hint": token_cnt,
            "functions": list(rel_map.keys()),
            "relatives": list(rel_map.values())
        }
        all_records.append(record)

    return pd.DataFrame(all_records)

if __name__ == "__main__":
    df = convert_to_group_df()
    if not df.empty:
        print("\n✅ 최종 group_df 요약:")
        print(df[["file", "id", "token_hint", "functions", "relatives"]])
