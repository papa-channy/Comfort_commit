-- =====================================================================================
-- 파일: 00_common_functions_and_types.sql
-- 설명: 데이터베이스 스키마 전체에서 공통적으로 사용되는 PostgreSQL 함수 및 ENUM 타입을 정의합니다.
--       이 스크립트는 다른 모든 테이블 생성 스크립트보다 먼저 실행되어야 합니다.
-- 대상 DB: PostgreSQL Primary RDB
-- =====================================================================================

-- 이전 실행 시 발생할 수 있는 오류를 방지하기 위해 기존 객체 삭제 (개발 단계에서만 사용)
-- DROP FUNCTION IF EXISTS set_updated_at() CASCADE;
-- DROP FUNCTION IF EXISTS delete_expired_sessions() CASCADE;
-- DROP FUNCTION IF EXISTS expire_rewards() CASCADE;
-- DROP FUNCTION IF EXISTS insert_user_plan_history() CASCADE;
-- DROP TYPE IF EXISTS user_account_type CASCADE;
-- DROP TYPE IF EXISTS plan_key_enum CASCADE;
-- DROP TYPE IF EXISTS reward_status_enum CASCADE;
-- DROP TYPE IF EXISTS deletion_request_status_enum CASCADE;
-- -- 추가적으로 04_repo_module 에서 정의했으나, 좀 더 범용적으로 쓰일 수 있는 ENUM이 있다면 이곳으로 이동 고려.
-- -- 예: repo_vcs_platform_enum, repo_visibility_enum 등 (단, repo 모듈 특화적이라면 그대로 두는 것이 맞음)

-- -------------------------------------------------------------------------------------
-- I. 공통 함수 (Common Functions)
-- -------------------------------------------------------------------------------------

-- 설명: 테이블의 row가 업데이트될 때마다 'updated_at' 컬럼을 현재 시각으로 자동 설정하는 트리거 함수입니다.
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW(); -- CURRENT_TIMESTAMP와 동일하게 타임존 포함 현재 시각
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION set_updated_at() IS '행 업데이트 시 updated_at 컬럼을 현재 시각으로 자동 설정하는 트리거 함수입니다.';


-- 설명: 만료된 사용자 세션을 삭제하는 함수입니다. 주기적인 스케줄러(예: pg_cron)를 통해 호출되는 것을 의도합니다.
-- 참조: 01_user_module/03_user_session.sql
CREATE OR REPLACE FUNCTION delete_expired_sessions()
RETURNS VOID AS $$
BEGIN
  DELETE FROM user_session WHERE expires_at < NOW();
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION delete_expired_sessions() IS '만료 시간이 지난 사용자 세션을 삭제합니다. 주기적 스케줄러(예: pg_cron)에 의해 호출되도록 설계되었습니다.';


-- 설명: 만료된 사용자 보상의 상태를 'expired'로 업데이트하는 함수입니다. 주기적인 스케줄러를 통해 호출되는 것을 의도합니다.
-- 참조: 03_plan_and_reward_module/03_user_reward_log.sql
CREATE OR REPLACE FUNCTION expire_rewards()
RETURNS VOID AS $$
BEGIN
  UPDATE user_reward_log
  SET reward_status = 'expired' -- reward_status_enum 타입으로 캐스팅은 값 자체가 유효하면 자동 수행됨
  WHERE reward_status = 'active'
    AND reward_expire_at IS NOT NULL
    AND reward_expire_at < NOW();
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION expire_rewards() IS '만료일이 지난 활성 상태의 보상을 ''expired'' 상태로 업데이트합니다. 주기적 스케줄러에 의해 호출되도록 설계되었습니다.';


-- 설명: user_plan 테이블의 plan_key가 변경될 때 user_plan_history 테이블에 변경 이력을 자동으로 기록하는 트리거 함수입니다.
-- 참조: 03_plan_and_reward_module/01_user_plan.sql, 02_user_plan_history.sql
-- 주의: 이 함수는 user_plan_history 테이블의 최종 컬럼 구조 및 plan_catalog 와의 연동을 고려하여
--       애플리케이션 또는 트리거 생성 시점에 구체적인 VALUES가 채워져야 합니다.
--       현재는 플레이스홀더 성격의 예시입니다.
CREATE OR REPLACE FUNCTION insert_user_plan_history_trigger_function() -- 함수명 변경 (일반 함수와 구분)
RETURNS TRIGGER AS $$
BEGIN
  -- 실제 INSERT 로직은 user_plan_history 테이블 구조 및 plan_catalog 연동 확정 후 구체화
  -- 다음은 예시 구조이며, OLD 및 NEW 레코드의 필드를 정확히 참조해야 합니다.
  INSERT INTO user_plan_history (
    uuid,
    old_plan_key,
    new_plan_key,
    old_plan_label,         -- (plan_catalog 등에서 조회 필요)
    new_plan_label,         -- (plan_catalog 등에서 조회 필요)
    old_price_usd,          -- (plan_catalog 등에서 조회 필요)
    new_price_usd,          -- (plan_catalog 등에서 조회 필요)
    was_trial,
    changed_by,             -- (애플리케이션에서 전달 또는 시스템 값)
    source_of_change,       -- (애플리케이션에서 전달 또는 시스템 값)
    effective_from,
    effective_until,
    change_note
    -- commit_usage_snapshot 등 스냅샷 값들도 OLD 레코드 또는 관련 집계에서 가져와야 함
  )
  VALUES (
    OLD.uuid,
    OLD.plan_key::TEXT,     -- ENUM을 TEXT로 저장 시
    NEW.plan_key::TEXT,
    (SELECT pc.plan_label FROM plan_catalog pc WHERE pc.plan_key = OLD.plan_key::TEXT), -- 예시: plan_catalog 참조
    (SELECT pc.plan_label FROM plan_catalog pc WHERE pc.plan_key = NEW.plan_key::TEXT), -- 예시: plan_catalog 참조
    (SELECT pc.monthly_price_usd FROM plan_catalog pc WHERE pc.plan_key = OLD.plan_key::TEXT), -- 예시
    (SELECT pc.monthly_price_usd FROM plan_catalog pc WHERE pc.plan_key = NEW.plan_key::TEXT), -- 예시
    OLD.is_trial_active,
    COALESCE(current_setting('comfort_commit.actor_uuid', TRUE), 'system_trigger'), -- 현재 사용자 또는 시스템
    'plan_change_trigger',
    OLD.current_period_ends_at, -- 이전 플랜 종료 시점
    NEW.current_period_started_at, -- 새 플랜 시작 시점
    'Plan changed from ' || OLD.plan_key::TEXT || ' to ' || NEW.plan_key::TEXT || ' via trigger.'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION insert_user_plan_history_trigger_function() IS 'user_plan.plan_key 변경 시 user_plan_history에 자동으로 이력을 기록하는 트리거 함수입니다. (세부 구현은 애플리케이션 로직 및 plan_catalog 연동에 따라 달라질 수 있습니다.)';


-- -------------------------------------------------------------------------------------
-- II. 공통 ENUM 타입 (Common ENUM Types)
-- -------------------------------------------------------------------------------------

-- `01_user_module/01_user_info.sql` 에서 사용
CREATE TYPE user_account_type_enum AS ENUM ( -- 이름에 _enum 접미사 추가하여 일관성 확보
    'personal',
    'team',
    'organization' -- 'org' 대신 'organization'으로 명확성 증대
);
COMMENT ON TYPE user_account_type_enum IS '사용자 계정의 유형을 정의합니다 (예: 개인, 팀, 조직).';


-- `03_plan_and_reward_module/01_user_plan.sql` 에서 사용
CREATE TYPE plan_key_enum AS ENUM (
    'free',
    'basic_monthly',
    'premium_monthly',
    'basic_annual',
    'premium_annual',
    'team_basic_monthly',
    'team_premium_monthly',
    'enterprise_custom',
    'trial_premium_monthly', -- 체험판 기간 명시 (월간 프리미엄 체험)
    'trial_basic_monthly'    -- (추가 가능성)
);
COMMENT ON TYPE plan_key_enum IS '시스템에서 제공하는 요금제의 내부 식별 키 값들의 집합입니다.';


-- `03_plan_and_reward_module/03_user_reward_log.sql` 에서 사용
CREATE TYPE reward_status_enum AS ENUM (
    'active',       -- 보상 활성 상태 (사용 가능)
    'used',         -- 보상 사용 완료
    'expired',      -- 보상 유효 기간 만료
    'revoked',      -- 관리자 또는 시스템에 의해 보상 취소
    'pending_claim' -- 사용자가 직접 수령해야 하는 보상 (선택적 상태)
);
COMMENT ON TYPE reward_status_enum IS '사용자에게 지급된 보상의 상태를 나타내는 값들의 집합입니다.';


-- `01_user_module/10_user_deletion_request.sql` 에서 사용
CREATE TYPE deletion_request_status_enum AS ENUM (
    'pending_user_confirmation', -- 'pending_confirmation' -> 명확하게
    'pending_processing',
    'processing_in_progress',
    'completed_data_deleted',    -- 'completed_deletion' -> 명확하게
    'completed_data_anonymized', -- 'completed_anonymization' -> 명확하게
    'rejected_by_admin',
    'cancelled_by_user',
    'error_during_processing',
    'retention_period_active'    -- (추가 가능성) 법적 보관 기간 동안 대기 상태
);
COMMENT ON TYPE deletion_request_status_enum IS '사용자 계정 탈퇴 요청의 처리 상태를 나타내는 값들의 집합입니다.';


-- (04_repo_module 에서 가져올 수 있는 범용 ENUM 예시 - 필요성 검토 후 이동)
-- -- `04_repo_module/01_repo_master/01_repo.sql` 에서 사용했었음
-- CREATE TYPE repo_vcs_platform_enum AS ENUM ('github', 'gitlab', 'bitbucket', 'azure_devops', 'aws_codecommit', 'gitea', 'other_vcs');
-- COMMENT ON TYPE repo_vcs_platform_enum IS '저장소가 호스팅되는 Version Control System 플랫폼 유형입니다.';

-- CREATE TYPE repo_visibility_enum AS ENUM ('public', 'private', 'internal');
-- COMMENT ON TYPE repo_visibility_enum IS '저장소의 공개 범위입니다.';

-- -- `04_repo_module/01_repo_master/02_repo_connections.sql` 에서 사용했었음
-- CREATE TYPE repo_connection_status_enum AS ENUM (
--     'pending_verification', 'connected', 'disconnected_by_user',
--     'error_authentication', 'error_permissions', 'error_not_found',
--     'syncing_in_progress', 'temporarily_unavailable', 'needs_re_authentication'
-- );
-- COMMENT ON TYPE repo_connection_status_enum IS '저장소와 Comfort Commit 서비스 간의 연동 상태입니다.';

-- CREATE TYPE repo_connection_method_enum AS ENUM (
--     'oauth_app', 'personal_access_token', 'ssh_key_reference',
--     'github_app_installation', 'gitlab_integration', 'bitbucket_app_password',
--     'github_codespaces', 'other_connection_method'
-- );
-- COMMENT ON TYPE repo_connection_method_enum IS '저장소에 접근하기 위해 우선적으로 사용되는 연결 방식입니다.';

-- -- `04_repo_module/01_repo_master/03_repo_access_permissions.sql` 에서 사용했었음
-- CREATE TYPE repo_access_level_enum AS ENUM ('owner', 'admin', 'maintainer', 'developer', 'reporter', 'viewer', 'guest', 'no_access_explicit');
-- COMMENT ON TYPE repo_access_level_enum IS 'Comfort Commit 서비스 내에서 사용자의 특정 저장소에 대한 접근 수준을 정의합니다.';

-- -- `04_repo_module/02_code_snapshots/01_code_snapshots.sql` 에서 사용했었음
-- CREATE TYPE snapshot_analysis_status_enum AS ENUM (
--     'pending', 'queued', 'processing_metadata', 'processing_diff', 'processing_code_elements', 'processing_embeddings',
--     'completed_successfully', 'completed_with_partial_data', 'failed_during_analysis', 'cancelled_by_user', 'error_internal_system'
-- );
-- COMMENT ON TYPE snapshot_analysis_status_enum IS '코드 스냅샷에 대한 Comfort Commit 내부 분석 작업의 진행 상태입니다.';

-- CREATE TYPE snapshot_trigger_event_enum AS ENUM (
--     'webhook_push_event', 'manual_sync_request', 'scheduled_repository_scan',
--     'initial_repository_registration', 'commit_generation_request_dependency', 'system_recovery_scan'
-- );
-- COMMENT ON TYPE snapshot_trigger_event_enum IS '이 코드 스냅샷 분석을 트리거한 이벤트의 유형입니다.';


SELECT 'Common functions and ENUM types created successfully.' AS status;