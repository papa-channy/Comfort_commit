-- =====================================================================================
-- 파일: 02_snapshot_file_instances.sql
-- 모듈: 04_repo_module / 03_files (파일 정보 관리)
-- 설명: 특정 코드 스냅샷 시점에서 각 파일의 구체적인 상태(경로, 내용 해시, 크기, 언어 등)를 기록합니다.
--       이는 file_uuidentities와 N:M 관계 (스냅샷을 통해)를 가질 수 있으며, 특정 스냅샷에서의 파일 "인스턴스"를 나타냅니다.
-- 대상 DB: PostgreSQL Primary RDB (파일 메타데이터 및 분석 입력 데이터)
-- 파티셔닝: 고려 가능 (snapshot_id 기준으로, 데이터가 매우 많아질 경우 - 스케일업 시)
-- MVP 중점사항: 스냅샷별 파일 상태, 내용 해시, 크기, 감지된 언어, 변경 유형, 필수 인덱스.
-- 스케일업 고려사항: RLS 적용, 파티셔닝, 바이너리 파일 처리 전략 구체화, 상세 변경 내용(diff) 참조 추가.
-- =====================================================================================

-- 테이블명: snapshot_file_instances
CREATE TABLE snapshot_file_instances (
    snapshot_file_uuid id PRIMARY KEY DEFAULT gen_random_id(), -- 스냅샷 내 파일 인스턴스의 고유 식별자 (PK)
    snapshot_id id NOT NULL REFERENCES code_snapshots(snapshot_id) ON DELETE CASCADE, -- 이 파일 인스턴스가 속한 코드 스냅샷 (FK)
    file_uuidentity_id id NOT NULL REFERENCES file_uuidentities(file_uuidentity_id) ON DELETE RESTRICT, -- 이 파일 인스턴스의 원본 파일 식별자 (FK). 파일 식별자 삭제 시 이 인스턴스는 유지될 수 있도록 RESTRICT.
    
    current_file_path TEXT NOT NULL,                         -- 이 스냅샷에서의 파일 전체 경로 (rename/move 등으로 인해 file_uuidentities.initial_file_path와 다를 수 있음)
    directory_uuid id REFERENCES directory_structures(directory_uuid) ON DELETE SET NULL, -- 이 파일이 속한 디렉토리 (FK). 디렉토리 삭제 시 파일 인스턴스는 남되, 연결만 NULL.
    
    file_content_hash TEXT,                                  -- 파일 내용의 해시값 (예: SHA-256). 동일 내용 파일 식별 및 변경 감지에 사용.
                                                             -- (스케일업 시: 여러 해시 알고리즘 지원을 위해 JSONB 또는 별도 테이블 고려)
    file_size_bytes BIGINT,                                  -- 파일 크기 (bytes)
    line_of_code_count INT,                                  -- 텍스트 파일의 경우 실제 코드 라인 수 (주석/공백 제외 또는 포함 정책 결정 필요)
    detected_language file_detected_language_enum DEFAULT 'unknown_language', -- 파일 내용 기반으로 감지된 프로그래밍 언어 (04_repo_module/00_repo_enums_and_types.sql 정의 예정)
    is_binary BOOLEAN DEFAULT FALSE,                         -- 파일이 바이너리 형식인지 여부
    
    file_mode_bits TEXT,                                     -- 파일의 권한 모드 비트 (예: "100644", "100755")
    symlink_target_path TEXT,                                -- 만약 이 파일이 심볼릭 링크라면, 원본 대상 경로
    
    is_deleted_in_this_snapshot BOOLEAN DEFAULT FALSE,       -- 이 스냅샷에서 해당 파일이 (이전 스냅샷 대비) 삭제된 것으로 처리되었는지 여부.
                                                             -- `change_type_from_parent_snapshot`이 'deleted'일 때 true.
    change_type_from_parent_snapshot file_change_type_enum,  -- 이 스냅샷의 부모 스냅샷(들) 대비 이 파일의 변경 유형. (04_repo_module/00_repo_enums_and_types.sql 정의 예정)

    -- 스케일업 시 고려:
    -- diff_summary_to_parent TEXT,                         -- 부모 스냅샷 대비 주요 변경 내용 요약 (선택적)
    -- content_external_ref_uuid TEXT,                        -- 파일 원본 내용이 S3 등 외부 저장소에 있을 경우 참조 uuid

    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,   -- 이 스냅샷 파일 인스턴스 레코드가 DB에 생성된 시각
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP    -- 이 레코드 정보가 마지막으로 수정된 시각 (트리거로 자동 관리)

    CONSTRAINT uq_snapshot_file_instances_snapshot_uuidentity UNIQUE (snapshot_id, file_uuidentity_id), -- 특정 스냅샷에서 특정 파일 식별자는 하나의 인스턴스만 가짐
    CONSTRAINT uq_snapshot_file_instances_snapshot_current_path UNIQUE (snapshot_id, current_file_path) -- 특정 스냅샷에서 동일한 현재 파일 경로는 유일해야 함
);

COMMENT ON TABLE snapshot_file_instances IS '특정 코드 스냅샷 시점에서 각 파일의 구체적인 상태(경로, 내용 해시, 크기, 언어, 변경 유형 등)를 기록합니다.';
COMMENT ON COLUMN snapshot_file_instances.snapshot_file_uuid IS '각 스냅샷 파일 인스턴스 레코드의 고유 id입니다.';
COMMENT ON COLUMN snapshot_file_instances.snapshot_id IS '이 파일 인스턴스가 포함된 code_snapshots 테이블의 스냅샷 id입니다.';
COMMENT ON COLUMN snapshot_file_instances.file_uuidentity_id IS '이 파일 인스턴스가 나타내는 원본 파일의 고유 식별자(file_uuidentities.file_uuidentity_id 참조)입니다.';
COMMENT ON COLUMN snapshot_file_instances.current_file_path IS '이 스냅샷 시점에서 해당 파일의 전체 경로입니다. 파일 이동이나 이름 변경 시 file_uuidentities.initial_file_path와 다를 수 있습니다.';
COMMENT ON COLUMN snapshot_file_instances.directory_uuid IS '이 파일이 위치하는 디렉토리의 uuid (directory_structures.directory_uuid 참조)입니다.';
COMMENT ON COLUMN snapshot_file_instances.file_content_hash IS '이 스냅샷 시점에서의 파일 내용에 대한 해시값입니다. 동일 내용 파일 감지 및 변경 여부 확인에 사용됩니다.';
COMMENT ON COLUMN snapshot_file_instances.file_size_bytes IS '파일의 크기 (바이트 단위) 입니다.';
COMMENT ON COLUMN snapshot_file_instances.line_of_code_count IS '텍스트 기반 파일의 경우, 실제 코드 라인 수입니다. 계산 정책(주석/공백 포함 여부)은 시스템 전반에 걸쳐 일관되어야 합니다.';
COMMENT ON COLUMN snapshot_file_instances.detected_language IS '파일 내용 분석을 통해 감지된 프로그래밍 또는 마크업 언어입니다 (04_repo_module/00_repo_enums_and_types.sql 정의된 file_detected_language_enum 값).';
COMMENT ON COLUMN snapshot_file_instances.is_binary IS '파일 내용이 텍스트가 아닌 바이너리 데이터인지 여부를 나타냅니다.';
COMMENT ON COLUMN snapshot_file_instances.file_mode_bits IS '파일 시스템에서의 파일 권한 모드 비트입니다 (예: Git의 "100644").';
COMMENT ON COLUMN snapshot_file_instances.symlink_target_path IS '이 파일이 심볼릭 링크인 경우, 링크가 가리키는 원본 대상의 경로입니다. 일반 파일인 경우 NULL입니다.';
COMMENT ON COLUMN snapshot_file_instances.is_deleted_in_this_snapshot IS '이 파일이 이전 스냅샷에 비해 현재 스냅샷에서 삭제된 것으로 간주되는지 여부입니다. 주로 change_type_from_parent_snapshot이 "deleted"일 때 TRUE가 됩니다.';
COMMENT ON COLUMN snapshot_file_instances.change_type_from_parent_snapshot IS '이전 스냅샷(또는 부모 커밋)과 비교했을 때 이 파일 인스턴스가 어떤 유형의 변경(추가, 수정, 삭제 등)을 겪었는지 나타냅니다 (04_repo_module/00_repo_enums_and_types.sql 정의된 file_change_type_enum 값).';
COMMENT ON COLUMN snapshot_file_instances.created_at IS '이 스냅샷 파일 인스턴스 레코드가 데이터베이스에 처음 생성된 시각입니다.';
COMMENT ON COLUMN snapshot_file_instances.updated_at IS '이 스냅샷 파일 인스턴스 정보가 마지막으로 수정된 시각입니다.';
COMMENT ON CONSTRAINT uq_snapshot_file_instances_snapshot_uuidentity ON snapshot_file_instances IS '하나의 코드 스냅샷 내에서 동일한 파일 식별자(file_uuidentity_id)를 가진 파일 인스턴스는 중복될 수 없습니다.';
COMMENT ON CONSTRAINT uq_snapshot_file_instances_snapshot_current_path ON snapshot_file_instances IS '하나의 코드 스냅샷 내에서는 동일한 현재 파일 경로(current_file_path)를 가진 파일 인스턴스가 중복될 수 없습니다.';


-- 인덱스
CREATE INDEX uuidx_snapshot_file_instances_snapshot_uuidentity ON snapshot_file_instances(snapshot_id, file_uuidentity_id); -- 특정 스냅샷의 특정 파일 인스턴스 조회 (UNIQUE 제약으로 커버되지만 명시적 생성도 가능)
CREATE INDEX uuidx_snapshot_file_instances_content_hash ON snapshot_file_instances(file_content_hash) WHERE file_content_hash IS NOT NULL; -- 동일 내용 해시를 가진 파일 인스턴스 조회
CREATE INDEX uuidx_snapshot_file_instances_language ON snapshot_file_instances(detected_language); -- 특정 언어로 감지된 파일 인스턴스 조회
CREATE INDEX uuidx_snapshot_file_instances_directory_uuid ON snapshot_file_instances(directory_uuid) WHERE directory_uuid IS NOT NULL; -- 특정 디렉토리에 속한 파일 인스턴스 조회
CREATE INDEX uuidx_snapshot_file_instances_snapshot_path ON snapshot_file_instances(snapshot_id, current_file_path); -- (UNIQUE 제약으로 커버되지만 명시적 생성도 가능)

-- updated_at 컬럼 자동 갱신 트리거
CREATE TRIGGER trg_set_updated_at_snapshot_file_instances
BEFORE UPDATE ON snapshot_file_instances
FOR EACH ROW EXECUTE FUNCTION set_updated_at();