from pathlib import Path
import json
from config.setting import cfg
from scripts.dataframe import load_df
from scripts.classify import classify_main
from scripts.upload_utils import get_file_path, do_git_commit, send_notification
from scripts.ext_info import to_safe_filename
import record.notion as notion

def perform_git_commit(commit_uuid: int, msg: str):
    import subprocess
    from pathlib import Path
    repo_path = Path("/your/repo/path")  # 수정 필요

    try:
        subprocess.run(["git", "add", "."], cwd=repo_path, check=True)
        subprocess.run(["git", "commit", "-m", msg], cwd=repo_path, check=True)
        subprocess.run(["git", "push"], cwd=repo_path, check=True)
    except Exception as e:
        print(f"[Git] Commit 실패: {e}")

def upload_main():
    timestamp = cfg.get_timestamp()  # ✅ 고정값 사용
    log_file = cfg.init_log_file(timestamp)
    paths = cfg.get_results_path(timestamp)

    strategy_df = load_df(paths["strategy"])
    if strategy_df is None or strategy_df.empty:
        cfg.log("❌ strategy_df 없음 → 업로드 중단", log_file)
        return

    result = classify_main()
    commit_msgs = result["commit"]
    fx_summary = result["fx_summary"]
    notify = result["notify"]

    strategy_map = strategy_df.set_index("File").to_dict(orient="index")
    commit_result = {}
    commit_groups = {"success": [], "fallback": [], "fail": []}

    for file in strategy_df["File"]:
        row = strategy_map.get(file)
        if not row:
            cfg.log(f"⚠️ strategy_df에 {file} 없음", log_file)
            commit_result[file] = "❌"
            commit_groups["fail"].append(file)
            continue

        filepath = Path(row["path"]) / to_safe_filename(file)

        if file in commit_msgs:
            msg = commit_msgs[file]
            success = do_git_commit(filepath, msg, lambda m: cfg.log(m, log_file))
            commit_result[file] = "✅" if success else "❌"
            commit_groups["success" if success else "fail"].append(file)
        else:
            dummy_msg = f"chore(auto): {file} 변경사항 (no LLM commit message)"
            success = do_git_commit(filepath, dummy_msg, lambda m: cfg.log(m, log_file))
            commit_result[file] = "⚠️ fallback" if success else "❌"
            commit_groups["fallback" if success else "fail"].append(file)

    cfg.log(f"✅ Git 커밋 결과 요약:\n{json.dumps(commit_result, ensure_ascii=False, indent=2)}", log_file)

    notify_text = (
        f"{notify['summary']}\n\n📌 비용 요약: {notify['cost_total']}\n"
        + "\n".join(notify["commits"][:5])
    )
    if commit_groups["fail"]:
        notify_text += f"\n🚫 커밋 실패 파일: {', '.join(commit_groups['fail'])}"
    if commit_groups["fallback"]:
        notify_text += f"\n⚠️ 메시지 없이 커밋된 파일: {', '.join(commit_groups['fallback'])}"
    if notify.get("review_files"):
        notify_text += f"\n🧐 수동 검토 대상: {', '.join(notify['review_files'])}"

    send_notification(["kakao", "slack", "discord", "gmail"], notify_text, lambda m: cfg.log(m, log_file))

    notion_failures = []
    for file, text in fx_summary.items():
        try:
            notion.upload_fx_record(file, text)
        except Exception as e:
            notion_failures.append(file)
            cfg.log(f"[NOTION] {file} 업로드 실패: {e}", log_file)

    if notion_failures:
        cfg.log(f"[NOTION] 업로드 실패 파일 목록: {notion_failures}", log_file)
        notify_text += f"\n📭 Notion 업로드 실패: {', '.join(notion_failures)}"

    cfg.log("✅ 전체 업로드 완료", log_file)
