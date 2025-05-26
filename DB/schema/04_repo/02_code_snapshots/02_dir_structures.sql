-- =====================================================================================
-- 파일: 02_directory_structures.sql
-- 모듈: 04_repo_module / 02_code_snapshots (코드 스냅샷 관리)
-- 설명: 특정 코드 스냅샷 시점에서의 저장소 디렉토리 구조를 계층적으로 저장합니다.
--       각 레코드는 하나의 디렉토리를 나타냅니다.
-- 대상 DB: PostgreSQL Primary RDB (코드 구조 메타데이터)
-- 파티셔닝: 고려 가능 (snapshot_id 기준으로, 매우 큰 저장소의 많은 스냅샷 관리 시 - 스케일업 시)
-- MVP 중점사항: 스냅샷별 디렉토리 경로, 부모-자식 관계, 중첩 레벨, 필수 인덱스.
-- 스케일업 고려사항: RLS 적용, 파티셔닝, 디렉토리별 통계(파일 수, 하위 디렉토리 수) 요약 정보 추가, tree_structure_json 최적화.
-- =====================================================================================

-- 테이블명: directory_structures
CREATE TABLE directory_structures (
    directory_uuid id PRIMARY KEY DEFAULT gen_random_id(), -- 디렉토리 레코드의 고유 식별자 (PK)
    snapshot_id id NOT NULL REFERENCES code_snapshots(snapshot_id) ON DELETE CASCADE, -- 이 디렉토리 구조가 속한 코드 스냅샷 (FK)
    
    parent_directory_uuid id REFERENCES directory_structures(directory_uuid) ON DELETE CASCADE, -- 부모 디렉토리의 uuid (최상위 디렉토리의 경우 NULL)
                                                                                             -- 자식 디렉토리는 부모가 삭제되면 함께 삭제 (계층 구조 유지)
    directory_path_text TEXT NOT NULL,                         -- 저장소 루트로부터의 전체 디렉토리 경로 (예: "src/main/java/com/example")
    directory_name TEXT NOT NULL,                              -- 해당 디렉토리의 이름 (예: "example")
    nesting_level INT NOT NULL CHECK (nesting_level >= 0),     -- 루트 디렉토리로부터의 중첩 깊이 (루트는 0)
    
    -- 스케일업 시 고려: 디렉토리 내 파일 수, 하위 디렉토리 수, 총 크기 등 요약 정보
    -- file_count_in_dir INT,
    -- subdirectory_count_in_dir INT,

    tree_structure_json JSONB,                                 -- 이 디렉토리 하위의 파일 및 서브디렉토리 목록을 간략하게 표현한 JSON (선택적, UI 표시 최적화용 또는 빠른 탐색용).
                                                               -- 예: {"files": ["file1.py", "file2.js"], "dirs": ["subdir1", "subdir2"]}
    
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,   -- 이 디렉토리 레코드가 DB에 생성된 시각
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP    -- 이 디렉토리 레코드 정보가 마지막으로 수정된 시각 (트리거로 자동 관리)

    CONSTRAINT uq_directory_structures_snapshot_dir_path UNIQUE (snapshot_id, directory_path_text) -- 동일 스냅샷 내에 중복된 전체 디렉토리 경로 방지
);

COMMENT ON TABLE directory_structures IS '특정 코드 스냅샷의 디렉토리 계층 구조를 나타냅니다. 각 레코드는 하나의 디렉토리를 의미합니다.';
COMMENT ON COLUMN directory_structures.directory_uuid IS '각 디렉토리 항목의 고유 식별 id입니다.';
COMMENT ON COLUMN directory_structures.snapshot_id IS '이 디렉토리 구조가 포함된 code_snapshots 테이블의 스냅샷 id입니다.';
COMMENT ON COLUMN directory_structures.parent_directory_uuid IS '이 디렉토리의 바로 상위 부모 디렉토리의 uuid (directory_structures.directory_uuid 참조)입니다. 루트 디렉토리의 경우 NULL 값을 가집니다.';
COMMENT ON COLUMN directory_structures.directory_path_text IS '저장소의 루트 디렉토리로부터 해당 디렉토리까지의 전체 경로 문자열입니다 (예: "src/main/java").';
COMMENT ON COLUMN directory_structures.directory_name IS '해당 디렉토리의 이름입니다 (예: "java").';
COMMENT ON COLUMN directory_structures.nesting_level IS '루트 디렉토리(0)로부터 해당 디렉토리까지의 중첩 단계(깊이)입니다.';
COMMENT ON COLUMN directory_structures.tree_structure_json IS '선택적으로, 해당 디렉토리 바로 하위의 파일 및 서브디렉토리 목록을 JSON 형태로 저장하여 UI 등에서 빠르게 트리를 구성하는 데 사용될 수 있습니다.';
COMMENT ON COLUMN directory_structures.created_at IS '이 디렉토리 레코드가 데이터베이스에 처음 생성된 시각입니다.';
COMMENT ON COLUMN directory_structures.updated_at IS '이 디렉토리 구조 정보가 마지막으로 수정된 시각입니다.';
COMMENT ON CONSTRAINT uq_directory_structures_snapshot_dir_path ON directory_structures IS '하나의 코드 스냅샷 내에서는 동일한 전체 디렉토리 경로가 중복으로 존재할 수 없습니다.';

-- 인덱스
CREATE INDEX uuidx_directory_structures_snapshot_parent ON directory_structures(snapshot_id, parent_directory_uuid); -- 특정 스냅샷의 특정 부모 디렉토리 하위 항목 조회
CREATE INDEX uuidx_directory_structures_snapshot_path ON directory_structures(snapshot_id, directory_path_text); -- 스냅샷 내 경로 검색 (UNIQUE 제약으로 커버되지만 명시적 생성도 가능)
CREATE INDEX uuidx_directory_structures_path_prefix ON directory_structures(directory_path_text text_pattern_ops); -- 경로 prefix 검색 최적화 (예: 'src/main/%' 검색)

-- updated_at 컬럼 자동 갱신 트리거
CREATE TRIGGER trg_set_updated_at_directory_structures
BEFORE UPDATE ON directory_structures
FOR EACH ROW EXECUTE FUNCTION set_updated_at();