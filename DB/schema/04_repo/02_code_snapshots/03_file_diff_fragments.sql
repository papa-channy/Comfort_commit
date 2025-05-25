-- =====================================================================================
-- 파일: 03_file_diff_fragments.sql
-- 모듈: 04_repo_module / 02_code_snapshots (스냅샷 시점 구조 저장)
-- 설명: 특정 스냅샷에서 변경된 파일들의 Diff 정보를 저장합니다.
--       LLM 프롬프트 입력에 활용될 수 있도록 변경된 라인, 유형 등의 요약 정보를 포함하며,
--       필요에 따라 원본 Diff 데이터는 외부 저장소(예: S3)에 저장하고 참조 ID를 가질 수 있습니다.
-- 대상 DB: PostgreSQL Primary RDB
-- 파티셔닝: 대량의 Diff 데이터 발생 시 고려 가능 (예: snapshot_id 또는 created_at 기준)
-- MVP 중점사항: 스냅샷 파일별 Diff 조각 정보, 변경 유형, 변경 라인, LLM 활용을 위한 핵심 정보.
-- 스케일업 고려사항: RLS, 파티셔닝, 외부 저장소 연동 강화, Hunk 단위 상세 분석, Diff 파싱 라이브러리와의 연동.
-- =====================================================================================

CREATE TABLE file_diff_fragments (
    diff_fragment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(), -- Diff 조각 레코드의 고유 식별자

    snapshot_file_id UUID NOT NULL REFERENCES snapshot_file_instances(snapshot_file_id) ON DELETE CASCADE,
    -- 이 Diff 정보가 속한 스냅샷의 특정 파일 인스턴스 (snapshot_file_instances.snapshot_file_id 참조)
    -- ON DELETE CASCADE: 부모 스냅샷 파일 인스턴스가 삭제되면 해당 Diff 정보도 함께 삭제

    -- Diff 요약 정보 (LLM 프롬프트용)
    change_type diff_change_type_enum NOT NULL, -- 변경 유형 (예: 'ADDED', 'MODIFIED', 'DELETED', 'RENAMED', 'COPIED')
                                             -- (00_repo_enums_and_types.sql 에 정의될 ENUM)
    -- 변경된 라인 수 정보
    lines_added INT DEFAULT 0,
    lines_deleted INT DEFAULT 0,
    -- lines_modified INT, -- 일반적으로 added/deleted로 표현되므로 중복될 수 있으나, 필요시 추가

    -- 변경된 주요 코드 블록 또는 라인 범위 (간단한 요약 또는 시작/종료 라인)
    -- MVP에서는 단순 TEXT로 시작하거나, 더 구조화된 표현(예: JSONB)으로 확장 가능
    changed_lines_summary TEXT,
    -- 예: "L10-L15: 함수 시그니처 변경, L20-L25: 로직 추가" 또는
    -- JSONB: [{"start_line": 10, "end_line": 15, "description": "function signature change"}, ...]

    -- Hunk 단위 정보 (Git Diff의 Hunk 헤더 정보 등) - 스케일업 시 고려
    -- hunk_details JSONB,
    -- 예: [{"old_start_line": 5, "old_lines_count": 3, "new_start_line": 5, "new_lines_count": 7, "header_text": "@@ -5,3 +5,7 @@"}, ...]

    -- 원본 Diff 데이터 참조 (선택적)
    raw_diff_content TEXT, -- 짧은 Diff의 경우 직접 저장 가능 (PII 및 저장 공간 고려)
    external_diff_storage_url TEXT, -- 긴 Diff는 S3 등 외부 저장소에 저장 후 URL 또는 ID 참조
    external_diff_checksum TEXT,    -- 외부 저장된 Diff의 무결성 검증용 체크섬 (예: SHA256)

    -- LLM 처리 관련 메타데이터 (선택적)
    is_llm_input_candidate BOOLEAN DEFAULT TRUE, -- 이 Diff 조각이 LLM 입력 후보로 사용될 수 있는지 여부
    llm_processing_notes TEXT,                 -- LLM 처리 시 참고할 만한 특이사항 (예: "매우 큰 변경", "주석만 변경됨")

    --  auditing
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE file_diff_fragments IS '특정 스냅샷에서 변경된 파일의 Diff 정보를 요약하거나 원본을 참조하여 저장합니다. LLM 프롬프트 생성에 활용됩니다.';
COMMENT ON COLUMN file_diff_fragments.snapshot_file_id IS 'Diff 정보가 속한 스냅샷 내 파일 인스턴스의 ID (snapshot_file_instances.snapshot_file_id 참조)입니다.';
COMMENT ON COLUMN file_diff_fragments.change_type IS '파일의 변경 유형을 나타냅니다 (00_repo_enums_and_types.sql에 정의된 diff_change_type_enum 값).';
COMMENT ON COLUMN file_diff_fragments.lines_added IS '해당 Diff에서 추가된 라인 수입니다.';
COMMENT ON COLUMN file_diff_fragments.lines_deleted IS '해당 Diff에서 삭제된 라인 수입니다.';
COMMENT ON COLUMN file_diff_fragments.changed_lines_summary IS '변경된 주요 라인 범위나 코드 블록에 대한 텍스트 요약 또는 JSONB 형태의 구조화된 정보입니다.';
COMMENT ON COLUMN file_diff_fragments.raw_diff_content IS '짧은 원본 Diff 내용을 직접 저장하는 필드입니다. 민감 정보 및 저장 공간을 고려하여 사용합니다.';
COMMENT ON COLUMN file_diff_fragments.external_diff_storage_url IS '원본 Diff 데이터가 외부 저장소(예: S3)에 저장된 경우 해당 URL 또는 식별자입니다.';
COMMENT ON COLUMN file_diff_fragments.external_diff_checksum IS '외부 저장소에 저장된 Diff 데이터의 무결성 검증을 위한 체크섬 값입니다.';
COMMENT ON COLUMN file_diff_fragments.is_llm_input_candidate IS '이 Diff 조각이 LLM의 입력으로 사용될 후보인지 여부를 나타냅니다.';
COMMENT ON COLUMN file_diff_fragments.llm_processing_notes IS 'LLM이 이 Diff를 처리할 때 참고할 만한 추가적인 메모입니다.';


-- 인덱스
CREATE INDEX idx_file_diff_fragments_snapshot_file_id ON file_diff_fragments(snapshot_file_id);
CREATE INDEX idx_file_diff_fragments_change_type ON file_diff_fragments(change_type);
CREATE INDEX idx_file_diff_fragments_is_llm_candidate ON file_diff_fragments(is_llm_input_candidate) WHERE is_llm_input_candidate = TRUE;

-- updated_at 컬럼 자동 갱신 트리거 (00_common_functions_and_types.sql 에 set_updated_at 함수 정의 가정)
CREATE TRIGGER trg_set_updated_at_file_diff_fragments
BEFORE UPDATE ON file_diff_fragments
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- (00_repo_enums_and_types.sql 에 정의될 ENUM 예시)
-- CREATE TYPE diff_change_type_enum AS ENUM (
--     'ADDED',       -- 파일 추가
--     'MODIFIED',    -- 파일 내용 수정
--     'DELETED',     -- 파일 삭제
--     'RENAMED',     -- 파일 이름 변경 (내용 변경도 포함될 수 있음)
--     'COPIED',      -- 파일 복사
--     'TYPE_CHANGED' -- 파일 타입 변경 (예: 심볼릭 링크 -> 파일)
-- );