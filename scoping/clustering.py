from pathlib import Path
import pandas as pd
import tiktoken
from extract_select_features import FeatureRegistry
from conv_df import convert_to_group_df, load_debug_mode

def get_token_count_gpt4o(text: str) -> int:
    try:
        enc = tiktoken.encoding_for_model("gpt-4o")
        return len(enc.encode(text))
    except Exception:
        return len(text.split())

def get_split_count(n_fx: int) -> int:
    if n_fx <= 12:
        return 1
    elif n_fx <= 20:
        return 2
    elif n_fx <= 30:
        return 3
    else:
        return (n_fx - 1) // 10 + 1

def chunk_selected_fx(fx_list: list[str], split: int) -> list[list[str]]:
    chunked = []
    size = len(fx_list) // split
    for i in range(split - 1):
        chunked.append(fx_list[i * size:(i + 1) * size])
    chunked.append(fx_list[(split - 1) * size:])
    return chunked

def clustering_main(df: pd.DataFrame, repo: str = "default") -> pd.DataFrame:
    debug = load_debug_mode()
    updated_rows = []

    for i, row in df.iterrows():
        file_path = Path(row["file"])
        fx_list: list[str] = row["functions"]
        rel_lists: list[list[str]] = row["relatives"]

        try:
            text = file_path.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue

        if get_token_count_gpt4o(text) <= 5:
            if debug == "on":
                print(f"⚠️ 토큰 수 0 → 생략된 파일: {file_path}")
            continue

        if debug == "on":
            print(f"\n📂 파일: {file_path}")
            print("📎 import하고 있는 파일:\n  (없음)")
            print("🔗 함수별로 참조된 외부 파일:")
            for fx, rels in zip(fx_list, rel_lists):
                print(f"  🔸 {fx}() →")
                for r in rels:
                    print(f"    - {r}")

        selected_fx_group = []

        for fx, rels in zip(fx_list, rel_lists):
            rels = list(set(r for r in rels if Path(r).exists()))
            if not rels:
                continue
            if len(rels) < 3:
                rel_scores = [(r, FeatureRegistry.extract_weighted_score(file_path, Path(r), repo, use_execution=False)) for r in rels]
                rel_scores.sort(key=lambda x: x[1], reverse=True)
                selected_fx_group.append([r for r, _ in rel_scores])
                continue

            rel_scores = [(r, float(FeatureRegistry.extract_weighted_score(file_path, Path(r), repo, use_execution=False))) for r in rels]
            rel_scores.sort(key=lambda x: x[1], reverse=True)
            top_rels = rel_scores[:5]

            if top_rels[0][1] == top_rels[1][1]:
                selected_fx_group.append([r for r, _ in top_rels[:3]])
                continue

            diff = abs(top_rels[0][1] - top_rels[1][1])
            relative = top_rels[0][1] if top_rels[0][1] != 0 else 1.0

            # 🔥 기준을 낮게 설정해야 실행 기반 비교가 제한됨
            if diff / relative < 0.1:  # 또는 단순히: if diff < 0.005:
                rescored = [
                    (r, float(FeatureRegistry.extract_weighted_score(file_path, Path(r), repo, use_execution=True)))
                    for r, _ in top_rels
                ]
                rescored.sort(key=lambda x: x[1], reverse=True)
                selected_fx_group.append([r for r, _ in rescored[:3]])
            else:
                selected_fx_group.append([r for r, _ in top_rels[:3]])

        if not selected_fx_group:
            continue

        split_count = get_split_count(sum(len(r) for r in selected_fx_group))
        grouped_fx = chunk_selected_fx(selected_fx_group, split_count)
        updated_rows.append({
            "file": str(file_path),
            "id": row.get("id", "N/A"),
            "selected_fx": selected_fx_group,
            "split_group": split_count,
            "fx_grouped": grouped_fx
        })

    return pd.DataFrame(updated_rows)


if __name__ == "__main__":
    df = convert_to_group_df()
    if not df.empty:
        final_df = clustering_main(df)
        pd.set_option("display.max_columns", None)
        pd.set_option("display.wuuidth", 160)
        print(final_df)