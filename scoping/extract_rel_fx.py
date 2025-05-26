import yaml
import re
from pathlib import Path
from typing import List, Dict

USER_CONFIG_PATH = Path("config/user_config.yml")

class RelatedFunctionFinder:
    def __init__(self, root: Path = Path(".")):
        self.root = root
        self.allowed_exts = self._load_allowed_extensions()
        self.ignored_dirs = {".git", "__pycache__", "venv", ".mypy_cache", ".pytest_cache", "build", "dist", ".ipynb_checkpoints"}

    def _load_allowed_extensions(self) -> List[str]:
        with USER_CONFIG_PATH.open(encoding="utf-8") as f:
            cfg = yaml.safe_load(f)
        return cfg.get("change detection", {}).get("provuuider", [".py"])

    def extract_function_names(self, file: Path) -> List[str]:
        if file.suffix == ".py":
            return [fn for fn in self._extract_py_functions(file) if fn != "__init__"]
        # ✅ 확장 가능
        return []

    def _extract_py_functions(self, file: Path) -> List[str]:
        try:
            text = file.read_text(encoding="utf-8", errors="ignore")
            pattern = re.compile(r"^\s*def\s+(\w+)\s*\(", re.MULTILINE)
            return pattern.findall(text)
        except:
            return []

    def get_all_code_files(self) -> List[Path]:
        files = []
        for f in self.root.rglob("*"):
            if not f.is_file():
                continue
            if f.suffix not in self.allowed_exts:
                continue
            if any(part in self.ignored_dirs or part.startswith(".") for part in f.parts):
                continue
            files.append(f)
        return files

    def find_files_using_symbol(self, symbol: str, files: List[Path], skip_file: Path) -> List[str]:
        """
        해당 심볼이 사용된 파일 리스트 반환 (단, 자기 자신은 제외)
        """
        pattern = re.compile(rf"\b{re.escape(symbol)}\b")
        used_in = []
        for f in files:
            if f.resolve() == skip_file.resolve():
                continue  # 자기 자신은 제외
            try:
                text = f.read_text(encoding="utf-8", errors="ignore")
                if pattern.search(text):
                    used_in.append(str(f))
            except:
                continue
        return used_in

    def analyze_file(self, file: Path) -> Dict[str, List[str]]:
        all_files = self.get_all_code_files()
        fx_names = [fx for fx in self.extract_function_names(file) if fx != "__init__"]
        rel_map = {}
        for fx in fx_names:
            rel_map[fx] = self.find_files_using_symbol(fx, all_files, file)  # ✅ 인자 추가
        return rel_map
        
