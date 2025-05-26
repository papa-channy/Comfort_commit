# scoping/import_flow.py

from pathlib import Path
from typing import List, Dict, Callable
import re

class ImportAnalyzer:
    def __init__(self, root: Path = Path(".")):
        self.root = root
        self.patterns = self._get_patterns()

    def _get_patterns(self) -> Dict[str, List[re.Pattern]]:
        return {
            ".py": [re.compile(r"^\s*import\s+(\S+)"),
                    re.compile(r"^\s*from\s+(\S+)\s+import")],
            ".js": [re.compile(r"import\s+.*\s+from\s+[\"'](.+)[\"']"),
                    re.compile(r"require\([\"'](.+)[\"']\)")],
            ".ts": [re.compile(r"import\s+.*\s+from\s+[\"'](.+)[\"']")],
            ".sh": [re.compile(r"(?:source|\.)\s+(.+\.sh)")],
            ".html": [re.compile(r'<script\s+.*src=["\'](.+?)["\']'),
                      re.compile(r'<link\s+.*href=["\'](.+?)["\']')],
            ".css": [re.compile(r'@import\s+url\(["\'](.+?)["\']\)')],
        }

    def extract_imports(self, file: Path) -> List[str]:
        imports = []
        ext = file.suffix
        try:
            text = file.read_text(encoding="utf-8", errors="ignore")
            for pattern in self.patterns.get(ext, []):
                imports.extend(pattern.findall(text))
        except Exception as e:
            print(f"⚠️ {file}: {e}")
        return imports

    def is_internal(self, imp: str) -> bool:
        if imp.startswith((".", "/")):
            return True
        parts = imp.split(".")
        for ext in [".py", ".js", ".ts", ".sh", ".html", ".css"]:
            canduuidate = self.root.joinpath(*parts).with_suffix(ext)
            if canduuidate.exists():
                return True
        if (self.root / imp / "__init__.py").exists():
            return True
        return False

    def filter_internal(self, imports: List[str]) -> List[str]:
        return [i for i in imports if self.is_internal(i)]

    def analyze_file(self, file: Path) -> List[str]:
        raw = self.extract_imports(file)
        return self.filter_internal(raw)

    def build_dependency_map(self, files: List[Path]) -> Dict[str, List[str]]:
        return {str(f): self.analyze_file(f) for f in files}
