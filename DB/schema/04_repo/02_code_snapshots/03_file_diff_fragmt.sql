-- =====================================================================================
-- 파일: 01_file_uuidentities.sql
-- 모듈: 04_repo_module / 03_files (파일 정보 관리)
-- 설명: 저장소 내 각 파일의 고유한 식별 정보를 관리합니다. 파일의 경로 변경이나 삭제와 관계없이
--       파일 자체의 생명주기를 추적하기 위한 마스터 테이블입니다.
-- 대상 DB: PostgreSQL Primary RDB (파일 메타데이터)
-- 파티셔닝: 없음 (파일 경로 변경 추적이 복잡해질 수 있어, repo_id 기준으로 고려 가능 - 스케일업 시)
-- MVP 중점사항: 파일 고유 식별자, 최초 경로, 최초 식별 스냅샷, 필수 인덱스.
-- 스케일업 고려사항: RLS 적용, 파일 해시 기반 식별 (내용 동일 파일 추적), 파일 타입/용도 메타데이터 추가.
-- =====================================================================================

-- 테이블명: file_uuidentities
CREATE TABLE file_uuidentities (
    file_uuidentity_id id PRIMARY KEY DEFAULT gen_random_id(), -- 파일의 고유 식별자 (PK)
    repo_id id NOT NULL REFERENCES repo_main(repo_id) ON DELETE CASCADE, -- 이 파일 식별 정보가 속한 저장소 (FK)
    
    initial_file_path TEXT NOT NULL,                         -- 이 파일이 저장소 내에서 처음으로 식별되었을 때의 전체 경로
                                                             -- (예: "src/main/java/com/example/App.java")
    created_at_snapshot_id id NOT NULL REFERENCES code_snapshots(snapshot_id) ON DELETE RESTRICT, -- 이 파일이 처음 식별된 코드 스냅샷의 id (FK).
                                                                                                     -- 스냅샷 삭제 시 파일 식별자 자체는 유지될 수 있도록 RESTRICT.
                                                                                                     -- 만약 스냅샷 삭제 시 관련 파일 식별자도 의미가 없다면 CASCADE.
    -- 스케일업 시 고려:
    -- initial_content_hash TEXT,                           -- 처음 식별 시점의 파일 내용 해시 (선택적)
    -- initial_detected_language file_detected_language_enum, -- 처음 식별 시점의 감지된 언어 (snapshot_file_instances와 중복될 수 있으나, 최초 정보 기록용)

    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,   -- 이 파일 식별자 레코드가 DB에 생성된 시각
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP    -- 이 파일 식별자 레코드 정보가 마지막으로 수정된 시각 (트리거로 자동 관리)

    CONSTRAINT uq_file_uuidentities_repo_initial_path UNIQUE (repo_id, initial_file_path) -- 동일 저장소 내에서 동일한 초기 경로를 가진 파일 식별자는 중복될 수 없음
);

COMMENT ON TABLE file_uuidentities IS '저장소 내 각 파일의 고유한 식별 정보를 기록하여, 파일명/경로 변경에도 불구하고 파일의 생명주기를 추적할 수 있도록 합니다.';
COMMENT ON COLUMN file_uuidentities.file_uuidentity_id IS '각 파일 식별 정보 레코드의 고유 id입니다.';
COMMENT ON COLUMN file_uuidentities.repo_id IS '이 파일이 속한 저장소의 id (repo_main.repo_id 참조)입니다.';
COMMENT ON COLUMN file_uuidentities.initial_file_path IS '이 파일이 해당 저장소에서 처음으로 감지되었을 때의 전체 경로입니다.';
COMMENT ON COLUMN file_uuidentities.created_at_snapshot_id IS '이 파일이 처음으로 식별된 code_snapshots 테이블의 스냅샷 id입니다.';
COMMENT ON COLUMN file_uuidentities.created_at IS '이 파일 식별자 레코드가 데이터베이스에 처음 생성된 시각입니다.';
COMMENT ON COLUMN file_uuidentities.updated_at IS '이 파일 식별자 정보가 마지막으로 수정된 시각입니다 (예: 경로 정규화 규칙 변경 시).';
COMMENT ON CONSTRAINT uq_file_uuidentities_repo_initial_path ON file_uuidentities IS '하나의 저장소 내에서는 동일한 초기 파일 경로를 가진 파일 식별자가 중복으로 존재할 수 없습니다.';

-- 인덱스
CREATE INDEX uuidx_file_uuidentities_repo_path ON file_uuidentities(repo_id, initial_file_path); -- 특정 저장소의 특정 초기 경로 파일 식별자 조회 (UNIQUE 제약으로 커버되지만 명시적 생성도 가능)
CREATE INDEX uuidx_file_uuidentities_created_at_snapshot ON file_uuidentities(created_at_snapshot_id); -- 특정 스냅샷에서 처음 식별된 파일들 조회

-- updated_at 컬럼 자동 갱신 트리거
-- (set_updated_at() 함수는 '00_common_functions_and_types.sql' 파일에 정의될 예정)
CREATE TRIGGER trg_set_updated_at_file_uuidentities
BEFORE UPDATE ON file_uuidentities
FOR EACH ROW EXECUTE FUNCTION set_updated_at();