-- =====================================================================================
-- 파일: 03_repo_access_permissions.sql
-- 모듈: 04_repo_module / 01_repo_main (저장소 기본 정보)
-- 설명: Comfort Commit 서비스 내에서 사용자별로 특정 저장소에 대한 접근 권한을 관리합니다.
--       이는 VCS 플랫폼 자체의 접근 권한과 별개로, 서비스 기능 사용 권한을 제어할 수 있습니다.
-- 대상 DB: PostgreSQL Primary RDB (접근 제어 데이터)
-- 파티셔닝: 없음
-- MVP 중점사항: 저장소-사용자-접근레벨 매핑, 권한 부여 주체, 유효 기간, 필수 인덱스, 표준 created_at/updated_at.
-- 스케일업 고려사항: RLS 적용, 권한 상속 규칙 (팀/조직 연동 시), 권한 변경 이력 로그 분리.
-- =====================================================================================

-- 테이블명: repo_access_permissions
CREATE TABLE repo_access_permissions (
    permission_uuid id PRIMARY KEY DEFAULT gen_random_id(), -- 권한 레코드의 고유 식별자 (PK)
    repo_id id NOT NULL REFERENCES repo_main(repo_id) ON DELETE CASCADE, -- 권한 대상 저장소 (FK)
    user_id id NOT NULL REFERENCES user_info(id) ON DELETE CASCADE, -- 권한을 부여받는 사용자 (FK)
    
    access_level repo_access_level_enum NOT NULL,          -- 이 사용자에게 부여된 접근 수준 (04_repo_module/00_repo_enums_and_types.sql 정의 예정)
    
    granted_by_user_id id REFERENCES user_info(id) ON DELETE SET NULL, -- 이 권한을 부여한 사용자 (시스템 또는 저장소 소유자/관리자)
    permission_start_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, -- 권한 효력 시작일
    permission_end_date TIMESTAMP,                          -- 권한 효력 만료일 (NULL이면 영구)
    
    notes TEXT,                                             -- 권한 설정 관련 관리자 메모
    
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, -- 이 권한 레코드가 생성된 시각
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP  -- 이 권한 레코드가 마지막으로 수정된 시각 (트리거로 자동 관리)

    CONSTRAINT uq_repo_user_permission UNIQUE (repo_id, user_id) -- 한 사용자는 한 저장소에 대해 하나의 접근 권한만 가짐 (중복 방지)
);

COMMENT ON TABLE repo_access_permissions IS 'Comfort Commit 서비스 내에서 특정 저장소에 대한 사용자별 접근 권한을 정의하고 관리합니다.';
COMMENT ON COLUMN repo_access_permissions.permission_uuid IS '각 권한 설정 레코드의 고유 식별 id입니다.';
COMMENT ON COLUMN repo_access_permissions.repo_id IS '권한이 적용되는 대상 저장소의 id (repo_main.repo_id 참조)입니다.';
COMMENT ON COLUMN repo_access_permissions.user_id IS '접근 권한을 부여받는 사용자의 id (user_info.id 참조)입니다.';
COMMENT ON COLUMN repo_access_permissions.access_level IS '부여된 접근 권한의 수준입니다 (04_repo_module/00_repo_enums_and_types.sql 정의된 repo_access_level_enum 값).';
COMMENT ON COLUMN repo_access_permissions.granted_by_user_id IS '이 접근 권한을 부여한 관리자 또는 시스템 주체의 사용자 id입니다.';
COMMENT ON COLUMN repo_access_permissions.permission_start_date IS '이 접근 권한이 효력을 발휘하기 시작하는 시각입니다.';
COMMENT ON COLUMN repo_access_permissions.permission_end_date IS '이 접근 권한의 효력이 만료되는 시각입니다. NULL인 경우 영구적인 권한을 의미합니다.';
COMMENT ON COLUMN repo_access_permissions.notes IS '이 권한 설정에 대한 추가적인 설명이나 관리자 메모입니다.';
COMMENT ON COLUMN repo_access_permissions.created_at IS '이 권한 레코드가 데이터베이스에 처음 생성된 시각입니다.';
COMMENT ON COLUMN repo_access_permissions.updated_at IS '이 권한 정보가 마지막으로 수정된 시각입니다.';
COMMENT ON CONSTRAINT uq_repo_user_permission ON repo_access_permissions IS '한 명의 사용자는 특정 저장소에 대해 하나의 접근 권한 레벨만 가질 수 있도록 보장합니다.';

-- 인덱스
CREATE INDEX uuidx_repo_access_permissions_user_id ON repo_access_permissions(user_id);
CREATE INDEX uuidx_repo_access_permissions_repo_id ON repo_access_permissions(repo_id);
CREATE INDEX uuidx_repo_access_permissions_repo_user_level ON repo_access_permissions(repo_id, user_id, access_level);

-- updated_at 컬럼 자동 갱신 트리거
CREATE TRIGGER trg_set_updated_at_repo_access_permissions
BEFORE UPDATE ON repo_access_permissions
FOR EACH ROW EXECUTE FUNCTION set_updated_at();