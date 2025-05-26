import os, json, subprocess, shutil, getpass
from pathlib import Path
import yaml
from dotenv import load_dotenv
import os
import subprocess
import sys
from pathlib import Path
import platform



def check_pycg_and_register():
    try:
        subprocess.run(["pycg", "--help"], capture_output=True, text=True, check=True)
        print("✅ pycg CLI 실행 확인 완료")
    except FileNotFoundError:
        print("❌ pycg 명령어를 찾을 수 없습니다")
        pycg_path = get_pycg_script_path()
        if platform.system() == "Windows":
            os.environ["PATH"] += os.pathsep + str(pycg_path)
            print(f"📌 PATH에 임시로 {pycg_path} 추가했습니다 (현재 세션)")
        else:
            add_path_to_bashrc(pycg_path)

if __name__ == "__main__":
    check_pycg_and_register()
from pathlib import Path
import os
import subprocess

def get_gitbash_path_line() -> str:
    """
    Windows + Git Bash에서 pycg 경로를 bashrc에 export하는 라인 생성
    """
    user_path = Path.home() / "AppData" / "Roaming" / "Python" / "Python313" / "Scripts"
    # Git Bash는 /c/Users/chan1/... 형식으로 표기
    bash_path = str(user_path).replace("\\", "/").replace("C:", "/c")
    return f'export PATH="{bash_path}:$PATH"'


def ensure_pycg_path_in_bashrc():
    bashrc = Path.home() / ".bashrc"
    export_line = get_gitbash_path_line()

    if bashrc.exists():
        content = bashrc.read_text()
        if export_line in content:
            print("✅ ~/.bashrc에 이미 pycg PATH가 등록되어 있습니다.")
            return

    with open(bashrc, "a", encoding="utf-8") as f:
        f.write(f"\n# [Auto] Added for pycg CLI access\n{export_line}\n")
    print("✅ ~/.bashrc에 pycg 경로를 등록했습니다.")
    print("🚀 `source ~/.bashrc`를 실행하거나 터미널을 재시작하면 적용됩니다.")


def test_pycg_cli():
    try:
        subprocess.run(["pycg", "--help"], capture_output=True, text=True, check=True)
        print("✅ pycg CLI 정상 실행 확인")
        return True
    except FileNotFoundError:
        print("❌ pycg 실행 실패: CLI 경로가 등록되어 있지 않습니다")
        return False


if __name__ == "__main__":
    if not test_pycg_cli():
        ensure_pycg_path_in_bashrc()
# ─────────────────────────────────────
def print_status(label, value, status="ok"):
    symbols = {"ok": "✅", "warn": "⚠️", "fail": "❌"}
    print(f"{symbols[status]} {label}: {value}")

def run(cmd): return subprocess.run(cmd, shell=True, text=True, capture_output=True).stdout.strip()

# 🔹 환경 변수 및 API KEY
def load_env_and_api_key():
    env_path = Path(__file__).parent / ".env"
    if env_path.exists():
        load_dotenv(dotenv_path=env_path)

    api_key = os.getenv("FIREWORKS_API_KEY", "")
    if not api_key:
        print_status(".env 설정", "FIREWORKS_API_KEY 누락", "fail")
        exit(1)

    return {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "Accept": "application/json"
    }, api_key

# 🔹 git 설정
def check_git_user_config():
    if not run("git config --global user.name"):
        subprocess.run('git config --global user.name "git-llm-user"', shell=True)
    if not run("git config --global user.email"):
        subprocess.run('git config --global user.email "git@llm.com"', shell=True)
    print_status("Git 사용자 설정", "등록됨")

def enforce_git_core_config():
    subprocess.run("git config --global core.autocrlf input", shell=True)
    subprocess.run("git config --global core.quotepath false", shell=True)
    print_status("core.autocrlf / quotepath", "적용 완료")

# 🔹 필수 파일 확인
def ensure_required_files():
    base = Path(__file__).parent.resolve()
    if not (base / ".gitattributes").exists():
        (base / ".gitattributes").write_text("* text=auto\n", encoding="utf-8")
    if not (base / ".editorconfig").exists():
        (base / ".editorconfig").write_text(
            "[*]\nend_of_line = lf\ninsert_final_newline = true\ncharset = utf-8\n", encoding="utf-8"
        )
    print_status("필수 설정 파일", "확인 완료")

# 🔹 Git 상태 확인
def check_git_repo():
    if subprocess.run("git rev-parse --is-insuuide-work-tree", shell=True).returncode != 0:
        print_status("Git 레포", ".git 없음", "fail")
        exit(1)
    print_status("Git 레포", "확인됨")

def check_git_remote():
    remote = run("git config --get remote.origin.url")
    if not remote:
        print_status("remote.origin.url", "없음", "fail"); exit(1)
    if subprocess.run(f"git ls-remote {remote}", shell=True).returncode != 0:
        print_status("원격 저장소 접근", "실패", "fail"); exit(1)
    print_status("원격 저장소", "접근 성공")

# 🔹 사용자 설정 YAML 로딩
def load_user_config():
    config_path = Path("config/user_config.yml")
    if not config_path.exists():
        print_status("user_config.yml", "없음", "fail")
        exit(1)
    return yaml.safe_load(config_path.read_text(encoding="utf-8"))

# 🔹 알림 플랫폼 점검
def check_notify_platforms(pf_list):
    import notify.discord as discord
    import notify.kakao as kakao
    import notify.gmail as gmail
    import notify.slack as slack

    ping_map = {"discord": discord.ping, "kakao": kakao.ping, "gmail": gmail.ping, "slack": slack.ping}

    for pf in pf_list:
        if pf not in ping_map:
            print_status(f"{pf} 알림 테스트", "지원되지 않음", "warn")
            continue
        if ping_map[pf]():
            print_status(f"{pf} 알림 테스트", "성공", "ok")
        else:
            print_status(f"{pf} 알림 테스트", "실패", "fail")
            exit(1)

# 🔹 Main
def main():
    print("\n🔍 check_err: 자동화 사전 점검 및 설정 시작\n")

    global HEADERS
    HEADERS, api_key = load_env_and_api_key()

    check_git_user_config()
    enforce_git_core_config()
    ensure_required_files()
    check_git_repo()
    check_git_remote()

    user_config = load_user_config()
    pf_list = user_config.get("notify", {}).get("platform", [])
    check_notify_platforms(pf_list)

    print("\n🎉 모든 점검 및 설정 완료. 자동화 준비 OK.\n")

if __name__ == "__main__":
    main()
