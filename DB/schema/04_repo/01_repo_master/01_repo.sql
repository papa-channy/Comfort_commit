-- =====================================================================================
-- 파일: 01_repo.sql
-- 모듈: 04_repo_module / 01_repositories (저장소 기본 정보)
-- 설명: 사용자가 Comfort Commit 서비스에 등록하는 소스 코드 저장소의 마스터 정보 및
--       서비스 운영에 필요한 주요 Git 메타데이터를 관리합니다.
-- 대상 DB: PostgreSQL Primary RDB (저장소 메타데이터)
-- 파티셔닝: 없음
-- MVP 중점사항: 핵심 식별 정보, Git 명령어 기반 주요 메타데이터(URL, 크기, 파일 수 등),
--             소유자, VCS 플랫폼, 가시성, 표준 created_at/updated_at.
-- 스케일업 고려사항: RLS 적용, 저장소별 상세 설정(JSONB), 메타데이터 주기적 업데이트 로직 및 last_analyzed_at 컬럼 추가.
-- =====================================================================================

-- ENUM 타입 정의 (필요시 04_repo_module/00_repo_enums_and_types.sql 파일로 통합 예정)
CREATE TYPE repo_vcs_platform_enum AS ENUM ('github', 'gitlab', 'bitbucket', 'other');
COMMENT ON TYPE repo_vcs_platform_enum IS '저장소가 호스팅되는 Version Control System 플랫폼 유형입니다.';

CREATE TYPE repo_visibility_enum AS ENUM ('public', 'private', 'internal');
COMMENT ON TYPE repo_visibility_enum IS '저장소의 공개 범위입니다.';

-- 테이블명: repo_master
CREATE TABLE repo_master (
    repo_uuid UUID PRIMARY KEY DEFAULT gen_random_uuid(),    -- 저장소의 고유 식별자 (PK)
    owner_uuid UUID NOT NULL REFERENCES user_info(uuid) ON DELETE RESTRICT, -- 이 저장소를 서비스에 등록한 소유 사용자
    
    name TEXT NOT NULL,                                      -- 저장소 이름 (VCS 플랫폼 기준)
    vcs_platform repo_vcs_platform_enum NOT NULL,            -- 저장소가 호스팅되는 VCS 플랫폼
    remote_url TEXT UNIQUE,                                  -- 'origin' 원격 저장소 URL (git config --get remote.origin.url 결과). 고유해야 함. [cite: 1, 9]
    visibility repo_visibility_enum DEFAULT 'private',      -- 저장소의 공개 범위 (VCS 플랫폼 기준)
    
    default_branch_name TEXT DEFAULT 'main',                 -- 저장소의 기본 브랜치명
    repository_created_at_on_platform TIMESTAMP,             -- VCS 플랫폼에서 저장소가 실제로 생성된 시각
    description_text TEXT,                                   -- 저장소 설명
    primary_language_detected TEXT,                          -- 주 사용 언어 (자동 감지 결과)
    
    -- Git 명령어 기반 분석 정보 (Comfort Commit 내부 분류 및 스코핑 전략에 활용)
    total_file_count INT,                                    -- 저장소 내 추적되는 총 파일 개수 (git ls-files | wc -l 또는 git ls-tree 결과 기반) [cite: 1, 18, 39]
    analyzable_file_count INT,                               -- 분석 대상 파일 개수 (예: 특정 확장자, .gitignore 제외)
    repository_size_kb BIGINT,                               -- 저장소의 디스크 사용량 (KB) (git count-objects -vH 결과 기반) [cite: 1, 20]
    last_analyzed_git_info_at TIMESTAMP,                     -- 위 Git 기반 분석 정보들이 마지막으로 업데이트된 시각

    archived_status BOOLEAN DEFAULT FALSE,                   -- VCS 플랫폼에서 아카이브된 상태인지 여부
    service_registration_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, -- Comfort Commit 서비스에 이 저장소가 등록된 시각
    
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, -- 이 레코드가 Comfort Commit DB에 생성된 시각
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP  -- 이 레코드의 메타데이터가 마지막으로 수정된 시각 (트리거로 자동 관리)

    CONSTRAINT uq_repo_master_owner_platform_name UNIQUE (owner_uuid, vcs_platform, name) -- 한 사용자가 동일 플랫폼에 동일 이름의 저장소를 중복 등록 방지
);

COMMENT ON TABLE repo_master IS 'Comfort Commit 서비스에 등록된 외부 소스 코드 저장소의 기본 마스터 정보 및 주요 Git 메타데이터를 저장합니다.';
COMMENT ON COLUMN repo_master.repo_uuid IS '저장소의 서비스 내 고유 식별 UUID입니다.';
COMMENT ON COLUMN repo_master.owner_uuid IS '이 저장소를 Comfort Commit 서비스에 등록하고 기본 소유권을 가지는 사용자의 UUID (user_info.uuid 참조)입니다.';
COMMENT ON COLUMN repo_master.name IS 'VCS 플랫폼에서의 저장소 이름입니다.';
COMMENT ON COLUMN repo_master.vcs_platform IS '저장소가 호스팅되는 Version Control System 플랫폼의 유형입니다.';
COMMENT ON COLUMN repo_master.remote_url IS '저장소의 원격 URL (예: git clone 주소) 입니다. 일반적으로 origin을 기준으로 합니다. [cite: 1, 9]';
COMMENT ON COLUMN repo_master.total_file_count IS 'Git이 추적하는 저장소 내 총 파일 수입니다. 레포 크기 분류에 사용될 수 있습니다. [cite: 1, 18, 39]';
COMMENT ON COLUMN repo_master.analyzable_file_count IS 'Comfort Commit 분석 대상이 되는 유효 파일 수입니다 (예: 데이터 파일, 바이너리 제외).';
COMMENT ON COLUMN repo_master.repository_size_kb IS '저장소가 디스크에서 차지하는 대략적인 크기(KB)입니다. 레포 크기 분류에 사용될 수 있습니다. [cite: 1, 20]';
COMMENT ON COLUMN repo_master.last_analyzed_git_info_at IS 'total_file_count, repository_size_kb 등의 Git 기반 분석 정보가 마지막으로 갱신된 시각입니다.';
COMMENT ON COLUMN repo_master.updated_at IS '이 저장소 메타데이터 레코드가 마지막으로 수정된 시각입니다.';

-- 인덱스
CREATE INDEX idx_repo_master_owner_uuid ON repo_master(owner_uuid);
CREATE INDEX idx_repo_master_vcs_platform ON repo_master(vcs_platform);
-- remote_url은 UNIQUE 제약조건에 의해 자동으로 인덱싱됩니다.

-- updated_at 컬럼 자동 갱신 트리거
CREATE TRIGGER trg_set_updated_at_repo_master
BEFORE UPDATE ON repo_master
FOR EACH ROW EXECUTE FUNCTION set_updated_at();