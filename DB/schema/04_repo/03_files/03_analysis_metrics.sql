-- =====================================================================================
-- 파일: 03_file_analysis_metrics.sql
-- 모듈: 04_repo_module / 03_files (파일 정보 관리)
-- 설명: 특정 스냅샷의 파일 인스턴스에 대한 다양한 "파일 메타정보" 및 "작업 흐름도 관련 정보"를
--       저장합니다. 이 정보는 LLM 호출 시 파일의 특성 및 상태를 이해시키는 데 활용될 수 있습니다.
--       (예: 코드 라인 수, 주석 비율, 최근 수정 강도, 의존성 복잡도 등)
-- 대상 DB: PostgreSQL Primary RDB
-- 파티셔닝: 고려 가능 (snapshot_file_uuid 또는 analysis_timestamp 기준으로, 데이터가 매우 많아질 경우)
-- MVP 중점사항: 파일 인스턴스별 메타정보 기록, 메트릭 타입(ENUM), 값(숫자/텍스트/JSON), 분석 도구/로직명, 필수 인덱스.
-- 스케일업 고려사항: RLS, 파티셔닝, 표준화된 분석 결과 포맷 정의, 메트릭 변화 추이 분석 기능 지원.
-- =====================================================================================

CREATE TABLE file_analysis_metrics (
    metric_uuid id PRIMARY KEY DEFAULT gen_random_id(),    -- 분석 메트릭 레코드의 고유 식별자 (PK)
    snapshot_file_uuid id NOT NULL REFERENCES snapshot_file_instances(snapshot_file_uuid) ON DELETE CASCADE,
    -- 이 분석 메트릭의 대상이 되는 스냅샷 파일 인스턴스 (snapshot_file_instances.snapshot_file_uuid 참조)

    metric_type metric_type_enum NOT NULL,                   -- 파일 메타정보 또는 분석 메트릭의 종류
                                                             -- (04_repo_module/00_repo_enums_and_types.sql 정의 예정)
                                                             -- 예: 'LINES_OF_CODE', 'COMMENT_RATIO', 'RECENT_CHANGE_INTENSITY', 'DEPENDENCY_COUNT_INTERNAL', 'EXPORTED_ELEMENT_COUNT'
    metric_value_numeric NUMERIC,                            -- 메트릭 값이 숫자인 경우 (예: 250, 0.35, 5)
    metric_value_text TEXT,                                  -- 메트릭 값이 텍스트인 경우 (예: 'High Change Activity', 'No External Dependencies')
    metric_value_json JSONB,                                 -- 메트릭 값이 복잡한 구조(객체 또는 배열)인 경우 JSONB로 저장
                                                             -- 예: {"imported_modules": ["os", "sys"], "exported_functions": ["func_a", "func_b"]}

    analyzed_by_tool_name TEXT NOT NULL,                     -- 이 분석을 수행한 도구 또는 내부 로직의 이름 (예: 'ComfortCommit_FileStat_Analyzer', 'ComfortCommit_Dep_Counter_v1', 'cloc', 'git_blame_analyzer')
    analysis_tool_version TEXT,                              -- 사용된 분석 도구/로직의 버전 (선택적)
    analysis_timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP, -- 분석이 수행되고 이 메트릭이 기록된 시각

    -- 스케일업 시 고려:
    -- metric_unit TEXT,                                    -- metric_value_numeric의 단위 (예: 'lines', '%', 'count')
    -- is_llm_input_relevant BOOLEAN DEFAULT TRUE,          -- 이 메트릭이 LLM 입력 컨텍스트로 사용될 수 있는지 여부

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP, -- 이 메트릭 레코드가 DB에 생성된 시각
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP  -- 이 레코드 정보가 마지막으로 수정된 시각 (트리거로 자동 관리)
);

COMMENT ON TABLE file_analysis_metrics IS '특정 스냅샷의 각 파일 인스턴스에 대한 파일 메타정보 및 작업 흐름도 관련 분석 결과를 저장합니다. LLM 입력 컨텍스트로 활용될 수 있습니다.';
COMMENT ON COLUMN file_analysis_metrics.metric_uuid IS '각 파일 분석 메트릭 레코드의 고유 id입니다.';
COMMENT ON COLUMN file_analysis_metrics.snapshot_file_uuid IS '이 분석 메트릭의 대상이 되는 snapshot_file_instances 테이블의 파일 인스턴스 id입니다.';
COMMENT ON COLUMN file_analysis_metrics.metric_type IS '파일 메타정보 또는 분석된 메트릭의 종류를 나타냅니다 (04_repo_module/00_repo_enums_and_types.sql 정의된 metric_type_enum 값).';
COMMENT ON COLUMN file_analysis_metrics.metric_value_numeric IS '메트릭 결과가 숫자 형태일 경우 그 값을 저장합니다.';
COMMENT ON COLUMN file_analysis_metrics.metric_value_text IS '메트릭 결과가 단순 텍스트 형태일 경우 그 값을 저장합니다.';
COMMENT ON COLUMN file_analysis_metrics.metric_value_json IS '메트릭 결과가 복잡한 JSON 구조(객체 또는 배열)일 경우 그 값을 저장합니다. 예를 들어, 파일 내 import/export 목록 등이 해당될 수 있습니다.';
COMMENT ON COLUMN file_analysis_metrics.analyzed_by_tool_name IS '해당 분석 메트릭을 생성한 분석 도구 또는 내부 로직의 이름입니다.';
COMMENT ON COLUMN file_analysis_metrics.analysis_tool_version IS '사용된 분석 도구 또는 로직의 버전 정보입니다.';
COMMENT ON COLUMN file_analysis_metrics.analysis_timestamp IS '이 분석 메트릭이 계산되고 시스템에 기록된 시각입니다.';
COMMENT ON COLUMN file_analysis_metrics.created_at IS '이 메트릭 레코드가 데이터베이스에 생성된 시각입니다.';
COMMENT ON COLUMN file_analysis_metrics.updated_at IS '이 분석 메트릭 정보가 마지막으로 수정된 시각입니다.';


-- 인덱스
CREATE INDEX uuidx_file_analysis_metrics_snapshot_file_type ON file_analysis_metrics(snapshot_file_uuid, metric_type); -- 특정 파일의 특정 메트릭 타입 조회
CREATE INDEX uuidx_file_analysis_metrics_type_tool ON file_analysis_metrics(metric_type, analyzed_by_tool_name); -- 특정 메트릭 타입 및 도구로 분석된 모든 파일 조회
CREATE INDEX uuidx_file_analysis_metrics_analysis_timestamp ON file_analysis_metrics(analysis_timestamp DESC); -- 최근 분석된 메트릭 조회

-- updated_at 컬럼 자동 갱신 트리거 (00_common_functions_and_types.sql 에 set_updated_at 함수 정의 가정)
CREATE TRIGGER trg_set_updated_at_file_analysis_metrics
BEFORE UPDATE ON file_analysis_metrics
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();
