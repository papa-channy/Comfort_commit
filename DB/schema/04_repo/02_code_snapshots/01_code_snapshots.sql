-- =====================================================================================
-- 파일: 01_code_snapshots.sql
-- 모듈: 04_repo_module / 02_code_snapshots (코드 스냅샷 관리)
-- 설명: 특정 Git 커밋 해시를 기준으로 저장소의 특정 시점 상태(스냅샷)에 대한 메타데이터를 관리합니다.
--       이 스냅샷은 Comfort Commit의 모든 코드 분석 및 커밋 생성 작업의 기준이 됩니다.
-- 대상 DB: PostgreSQL Primary RDB (코드 분석 기준 데이터)
-- 파티셔닝: 고려 가능 (repo_id, committed_at_on_platform 기준으로, 데이터가 매우 많아질 경우 - 스케일업 시)
-- MVP 중점사항: 스냅샷 식별 정보(커밋 해시), 부모 커밋, 커미터 정보, 분석 트리거 및 상태, 필수 인덱스.
-- 스케일업 고려사항: RLS 적용, 파티셔닝, 분석 결과 요약 정보 추가, 스냅샷 간의 비교 기능 지원.
-- =====================================================================================

-- 테이블명: code_snapshots
CREATE TABLE code_snapshots (
    snapshot_id id PRIMARY KEY DEFAULT gen_random_id(),    -- 코드 스냅샷의 고유 식별자 (PK)
    repo_id id NOT NULL REFERENCES repo_main(repo_id) ON DELETE CASCADE, -- 이 스냅샷이 속한 저장소 (FK)
    
    git_commit_hash TEXT NOT NULL,                               -- 해당 스냅샷의 기준이 되는 Git 커밋 해시 (SHA-1 또는 SHA-256)
    parent_commit_hashes TEXT[],                                 -- 이 커밋의 부모 커밋 해시 목록 (Merge commit의 경우 여러 개일 수 있음)
    commit_message_original TEXT,                                -- 원본 Git 커밋 메시지
    committer_name TEXT,                                         -- 원본 커밋의 커미터 이름
    committer_email TEXT,                                        -- 원본 커밋의 커미터 이메일
    committed_at_on_platform TIMESTAMP,                          -- Git 플랫폼(예: GitHub)에서의 실제 커밋 시각
    
    analysis_trigger_event snapshot_trigger_event_enum,         -- 이 스냅샷에 대한 분석을 시작하게 된 이벤트 유형 (04_repo_module/00_repo_enums_and_types.sql 정의 예정)
    analysis_start_time TIMESTAMP,                               -- Comfort Commit 내부 분석 시작 시각
    analysis_end_time TIMESTAMP,                                 -- Comfort Commit 내부 분석 완료 시각
    analysis_status snapshot_analysis_status_enum DEFAULT 'pending', -- Comfort Commit 내부 분석 상태 (04_repo_module/00_repo_enums_and_types.sql 정의 예정)
    analysis_error_details TEXT,                                 -- 분석 실패 시 상세 오류 메시지
    
    snapshot_created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP -- 이 스냅샷 레코드가 Comfort Commit DB에 생성된 시각
    -- updated_at은 분석 상태 변경 등에 따라 필요할 수 있으나, 스냅샷 자체의 메타데이터는 불변으로 간주하여 MVP에서는 제외.
    -- 필요시 추가하고 트리거 설정 가능.

    CONSTRAINT uq_code_snapshots_repo_commit_hash UNIQUE (repo_id, git_commit_hash) -- 한 저장소 내에서 특정 커밋 해시에 대한 스냅샷은 유일해야 함
);

COMMENT ON TABLE code_snapshots IS '특정 Git 커밋을 기준으로 생성된 저장소의 코드 스냅샷 메타데이터를 저장합니다. 모든 분석과 커밋 생성은 이 스냅샷을 기준으로 이루어집니다.';
COMMENT ON COLUMN code_snapshots.snapshot_id IS '코드 스냅샷 레코드의 고유 식별 id입니다.';
COMMENT ON COLUMN code_snapshots.repo_id IS '이 코드 스냅샷이 속한 저장소의 id (repo_main.repo_id 참조)입니다.';
COMMENT ON COLUMN code_snapshots.git_commit_hash IS '이 스냅샷의 기준이 되는 Git 커밋의 전체 해시값입니다.';
COMMENT ON COLUMN code_snapshots.parent_commit_hashes IS '이 스냅샷의 기준 커밋의 부모 커밋 해시 목록입니다. Merge commit인 경우 두 개 이상의 부모를 가질 수 있습니다.';
COMMENT ON COLUMN code_snapshots.commit_message_original IS 'VCS 플랫폼에 기록된 원본 커밋 메시지입니다.';
COMMENT ON COLUMN code_snapshots.committer_name IS 'VCS 플랫폼에 기록된 원본 커밋의 커미터 이름입니다.';
COMMENT ON COLUMN code_snapshots.committer_email IS 'VCS 플랫폼에 기록된 원본 커밋의 커미터 이메일입니다.';
COMMENT ON COLUMN code_snapshots.committed_at_on_platform IS 'VCS 플랫폼(GitHub, GitLab 등)에 해당 커밋이 기록된 실제 시각입니다.';
COMMENT ON COLUMN code_snapshots.analysis_trigger_event IS 'Comfort Commit 시스템이 이 스냅샷에 대한 분석을 시작하게 된 계기입니다 (예: Webhook push, 수동 동기화). 정의는 04_repo_module/00_repo_enums_and_types.sql 참조.';
COMMENT ON COLUMN code_snapshots.analysis_start_time IS 'Comfort Commit 시스템의 내부 코드 분석이 시작된 시각입니다.';
COMMENT ON COLUMN code_snapshots.analysis_end_time IS 'Comfort Commit 시스템의 내부 코드 분석이 완료된 시각입니다.';
COMMENT ON COLUMN code_snapshots.analysis_status IS 'Comfort Commit 시스템의 내부 코드 분석 작업 진행 상태입니다. 정의는 04_repo_module/00_repo_enums_and_types.sql 참조.';
COMMENT ON COLUMN code_snapshots.analysis_error_details IS '코드 분석 작업 중 오류가 발생한 경우, 해당 오류에 대한 상세 설명입니다.';
COMMENT ON COLUMN code_snapshots.snapshot_created_at IS '이 스냅샷 정보 레코드가 Comfort Commit 데이터베이스에 처음 생성된 시각입니다.';
COMMENT ON CONSTRAINT uq_code_snapshots_repo_commit_hash ON code_snapshots IS '동일한 저장소 내에서 동일한 Git 커밋 해시를 가진 스냅샷은 중복으로 생성될 수 없습니다.';

-- 인덱스
CREATE INDEX uuidx_code_snapshots_repo_commit_hash ON code_snapshots(repo_id, git_commit_hash); -- 특정 저장소의 특정 커밋 스냅샷 조회 (UNIQUE 제약으로 커버되지만 명시적 생성도 가능)
CREATE INDEX uuidx_code_snapshots_repo_status_created_at ON code_snapshots(repo_id, analysis_status, snapshot_created_at DESC); -- 특정 저장소의 분석 상태별 최근 스냅샷 조회
CREATE INDEX uuidx_code_snapshots_committed_at_on_platform ON code_snapshots(committed_at_on_platform DESC); -- 커밋 시간 기준 정렬/조회
CREATE INDEX uuidx_code_snapshots_analysis_trigger_event ON code_snapshots(analysis_trigger_event);