from pathlib import Path
from typing import Callable, Dict
from functools import wraps
import subprocess, time, re, json

def measure_time_and_log(func):
    @wraps(func)
    def wrapper(self, file_a: Path, file_b: Path) -> float:
        start = time.time()
        result = func(self, file_a, file_b)
        end = time.time()
        print(f"[✔] {func.__name__:<35} → {result:.4f}  (Time: {end - start:.2f}s)")
        return result
    return wrapper


class ExecutionFeatureExtractor:
    def __init__(self, timeout: float = 1.0):
        self.timeout = timeout

    def _run_and_trace(self, file: Path) -> dict:
        try:
            result = subprocess.run(
                ["python", str(file)],
                capture_output=True,
                text=True,
                timeout=self.timeout
            )
            return {"success": True, "stderr": result.stderr}
        except subprocess.CalledProcessError as e:
            return {"success": False, "stderr": e.stderr}
        except subprocess.TimeoutExpired:
            return {"success": False, "stderr": "TimeoutError"}
        except Exception as e:
            return {"success": False, "stderr": str(e)}

    def _last_trace_line(self, stderr: str) -> str:
        lines = stderr.strip().splitlines()
        return lines[-1].strip() if lines else ""

    def _error_type(self, stderr: str) -> str:
        match = re.search(r"(?<=\n)[\w]+Error(?=[:\s])", stderr)
        return match.group(0) if match else "UnknownError"

    @measure_time_and_log
    def error_type_overlap_score(self, file_a: Path, file_b: Path) -> float:
        err_a = self._error_type(self._run_and_trace(file_a)["stderr"])
        err_b = self._error_type(self._run_and_trace(file_b)["stderr"])
        return float(err_a == err_b)

    @measure_time_and_log
    def traceback_lastline_sim(self, file_a: Path, file_b: Path) -> float:
        line_a = self._last_trace_line(self._run_and_trace(file_a)["stderr"])
        line_b = self._last_trace_line(self._run_and_trace(file_b)["stderr"])
        return 1.0 if line_a == line_b else 0.0

    @measure_time_and_log
    def traceback_module_name_match(self, file_a: Path, file_b: Path) -> float:
        a = self._last_trace_line(self._run_and_trace(file_a)["stderr"])
        b = self._last_trace_line(self._run_and_trace(file_b)["stderr"])
        extract = lambda txt: re.findall(r"\b\w+\b", txt)
        tokens_a = set(extract(a))
        tokens_b = set(extract(b))
        return len(tokens_a & tokens_b) / len(tokens_a | tokens_b) if tokens_a and tokens_b else 0.0

    @measure_time_and_log
    def failed_execution_signal(self, file_a: Path, file_b: Path) -> float:
        a_fail = not self._run_and_trace(file_a)["success"]
        b_fail = not self._run_and_trace(file_b)["success"]
        return float(a_fail == b_fail)

    @measure_time_and_log
    def error_line_depth_ratio(self, file_a: Path, file_b: Path) -> float:
        def depth(stderr: str):
            return stderr.count("File \"")
        a_depth = depth(self._run_and_trace(file_a)["stderr"])
        b_depth = depth(self._run_and_trace(file_b)["stderr"])
        return abs(a_depth - b_depth) / max(a_depth, b_depth) if max(a_depth, b_depth) else 0.0


class FeatureRegistry:
    _registry: Dict[str, Callable[[Path, Path], float]] = {}

    @classmethod
    def register(cls, name: str):
        def decorator(func: Callable[[Path, Path], float]):
            cls._registry[name] = func
            return func
        return decorator
    @classmethod
    def extract_all(cls, file_a: Path, file_b: Path, use_execution: bool = True) -> Dict[str, float]:
        execution_features = {
            "error_type_overlap_score", "traceback_lastline_sim",
            "traceback_module_name_match", "failed_execution_signal",
            "error_line_depth_ratio"
        }
        results = {}
        for name, func in cls._registry.items():
            if not use_execution and name in execution_features:
                continue
            try:
                results[name] = float(func(file_a, file_b))
            except Exception:
                results[name] = 0.0
        return results

    @classmethod
    def load_weights(cls, repo: str = "default") -> Dict[str, float]:
        weight_path = Path("scoping/weight.json")
        feature_path = Path("scoping/feature.json")
        with weight_path.open(encoding="utf-8") as wf:
            weight_dict = json.load(wf)
        with feature_path.open(encoding="utf-8") as ff:
            feature_meta = json.load(ff)
        feature_names = [f["name"] for f in feature_meta]
        weights = weight_dict[repo]["weight"]
        return dict(zip(feature_names, weights))

    @classmethod
    def extract_weighted_score(
        cls,
        file_a: Path,
        file_b: Path,
        repo: str = "default",
        use_execution: bool = True
    ) -> float:
        # extract_all은 내부에서 use_execution에 따라 static만 추출 가능해야 함
        features = cls.extract_all(file_a, file_b, use_execution=use_execution)
        weights = cls.load_weights(repo)

        total = 0.0
        for f, val in features.items():
            try:
                score = float(val)
                weight = weights.get(f, 1.0)
                total += score * weight
            except (ValueError, TypeError):
                continue
        return total

    @classmethod
    def extract_static(cls, file_a: Path, file_b: Path) -> Dict[str, float]:
        """
        실행 기반 feature 제외하고 정적 feature만 추출
        """
        exclude = {
            "error_type_overlap_score",
            "traceback_lastline_sim",
            "traceback_module_name_match",
            "failed_execution_signal",
            "error_line_depth_ratio"
        }
        return {
            name: fn(file_a, file_b)
            for name, fn in cls._registry.items()
            if name not in exclude
        }
# 정적 Feature
@FeatureRegistry.register("def_jaccard")
def def_jaccard(file_a: Path, file_b: Path) -> float:
    try:
        a_text = file_a.read_text(encoding="utf-8", errors="ignore")
        b_text = file_b.read_text(encoding="utf-8", errors="ignore")
        a_defs = set(re.findall(r"def (\w+)", a_text))
        b_defs = set(re.findall(r"def (\w+)", b_text))
        if not a_defs and not b_defs:
            return 0.0
        return len(a_defs & b_defs) / len(a_defs | b_defs)
    except:
        return 0.0

@FeatureRegistry.register("import_jaccard")
def import_jaccard(file_a: Path, file_b: Path) -> float:
    try:
        pattern = re.compile(r"^\s*(?:from|import)\s+([\w\.]+)", re.MULTILINE)
        a_text = file_a.read_text(encoding="utf-8", errors="ignore")
        b_text = file_b.read_text(encoding="utf-8", errors="ignore")
        a_imports = set(pattern.findall(a_text))
        b_imports = set(pattern.findall(b_text))
        if not a_imports and not b_imports:
            return 0.0
        return len(a_imports & b_imports) / len(a_imports | b_imports)
    except:
        return 0.0

@FeatureRegistry.register("filename_semantic_jaccard")
def filename_semantic_jaccard(file_a: Path, file_b: Path) -> float:
    a_parts = set(file_a.stem.lower().replace("-", "_").split("_"))
    b_parts = set(file_b.stem.lower().replace("-", "_").split("_"))
    if not a_parts and not b_parts:
        return 0.0
    return len(a_parts & b_parts) / len(a_parts | b_parts)

@FeatureRegistry.register("folder_prefix_match")
def folder_prefix_match(file_a: Path, file_b: Path) -> float:
    a_parent = file_a.parent.parts
    b_parent = file_b.parent.parts
    match = sum(1 for a, b in zip(a_parent, b_parent) if a == b)
    return match / max(len(a_parent), len(b_parent)) if max(len(a_parent), len(b_parent)) > 0 else 0.0

@FeatureRegistry.register("module_level_overlap")
def module_level_overlap(file_a: Path, file_b: Path) -> float:
    a_mods = set(file_a.parts)
    b_mods = set(file_b.parts)
    if not a_mods and not b_mods:
        return 0.0
    return len(a_mods & b_mods) / len(a_mods | b_mods)


# 실행 기반 Feature
@FeatureRegistry.register("error_type_overlap_score")
def error_type_overlap_score(file_a: Path, file_b: Path) -> float:
    return ExecutionFeatureExtractor().error_type_overlap_score(file_a, file_b)

@FeatureRegistry.register("traceback_lastline_sim")
def traceback_lastline_sim(file_a: Path, file_b: Path) -> float:
    return ExecutionFeatureExtractor().traceback_lastline_sim(file_a, file_b)

@FeatureRegistry.register("traceback_module_name_match")
def traceback_module_name_match(file_a: Path, file_b: Path) -> float:
    return ExecutionFeatureExtractor().traceback_module_name_match(file_a, file_b)

@FeatureRegistry.register("failed_execution_signal")
def failed_execution_signal(file_a: Path, file_b: Path) -> float:
    return ExecutionFeatureExtractor().failed_execution_signal(file_a, file_b)

@FeatureRegistry.register("error_line_depth_ratio")
def error_line_depth_ratio(file_a: Path, file_b: Path) -> float:
    return ExecutionFeatureExtractor().error_line_depth_ratio(file_a, file_b)
