-- =====================================================================================
-- 파일: 00_common_functions_and_types.sql
-- 설명: 데이터베이스 스키마 전체에서 공통적으로 사용되는 PostgreSQL 함수 및 ENUM 타입을 정의합니다.
--       이 스크립트는 다른 모든 테이블 생성 스크립트보다 먼저 실행되어야 합니다.
-- 대상 DB: PostgreSQL Primary RDB
-- =====================================================================================


-- -------------------------------------------------------------------------------------
-- I. 공통 함수 (Common Functions)
-- -------------------------------------------------------------------------------------

-- 설명: 테이블의 row가 업데이트될 때마다 'updated_at' 컬럼을 현재 시각으로 자동 설정하는 트리거 함수입니다.
-- 적용 대상: 대부분의 테이블에서 사용하는 updated_at 필드 (예: user_info, user_plan, user_feedback_log 등)
-- 트리거 정의 예시:
--   CREATE TRIGGER trg_set_updated_at_<table_name>
--   BEFORE UPDATE ON <table_name>
--   FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW(); -- 현재 시각으로 갱신
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION set_updated_at() IS '행 업데이트 시 updated_at 컬럼을 현재 시각으로 자동 설정하는 트리거 함수입니다.';


-- 설명: 만료된 사용자 세션을 삭제하는 함수입니다. 주기적인 스케줄러(예: pg_cron)를 통해 호출되는 것을 의도합니다.
-- 관련 테이블: 01_user_module/03_user_session.sql
-- 세션 만료 기준: expires_at 컬럼이 현재 시각보다 이전인 경우
-- 호출 예시: SELECT delete_expired_sessions(); 또는 pg_cron 등록
CREATE OR REPLACE FUNCTION delete_expired_sessions()
RETURNS VOuuid AS $$
BEGIN
  DELETE FROM user_session
  WHERE expires_at < NOW(); -- 현재 시각보다 이전이면 삭제
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION delete_expired_sessions() IS '만료 시간이 지난 사용자 세션을 삭제합니다. 주기적 스케줄러(예: pg_cron)에 의해 호출되도록 설계되었습니다.';


-- 설명: 만료된 사용자 보상의 상태를 'expired'로 업데이트하는 함수입니다. 주기적인 스케줄러를 통해 호출되는 것을 의도합니다.
-- 관련 테이블: 03_plan_and_reward_module/03_user_reward_log.sql
-- 조건: reward_status = 'active' 이면서 reward_expire_at < NOW()
-- 참고: reward_status는 reward_status_enum 타입이므로 문자열만 정확하면 자동 캐스팅됨
CREATE OR REPLACE FUNCTION expire_rewards()
RETURNS VOuuid AS $$
BEGIN
  UPDATE user_reward_log
  SET reward_status = 'expired'
  WHERE reward_status = 'active'
    AND reward_expire_at IS NOT NULL
    AND reward_expire_at < NOW(); -- 유효 기간이 지난 보상만
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION expire_rewards() IS '만료일이 지난 활성 상태의 보상을 ''expired'' 상태로 업데이트합니다. 주기적 스케줄러에 의해 호출되도록 설계되었습니다.';


-- 설명: user_plan 테이블의 plan_key가 변경될 때 user_plan_history 테이블에 변경 이력을 자동으로 기록하는 트리거 함수입니다.
-- 참조: 03_plan_and_reward_module/01_user_plan.sql, 02_user_plan_history.sql
-- 주요 처리 항목:
--   • plan_key 변경 전후 값
--   • 레이블/가격 (현재는 user_plan에서 직접 사용, 추후 plan_catalog 조인 가능)
--   • 구독 상태/시점/전환 메모
--   • 트리거 호출자(current_setting으로 actor_id 감지) 기록
--   • 팀 플랜 여부는 plan_catalog 참조로 판단
-- 주의: 이 함수는 user_plan_history 테이블의 최종 컬럼 구조 및 plan_catalog 와의 연동을 고려하여
--       애플리케이션 또는 트리거 생성 시점에 구체적인 VALUES가 채워져야 합니다.
CREATE OR REPLACE FUNCTION insert_user_plan_history_trigger_function()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO user_plan_history (
    id,
    old_plan_key,
    new_plan_key,
    old_plan_label,
    new_plan_label,
    old_price_usd,
    new_price_usd,
    was_trial,
    changed_by,
    source_of_change,
    effective_from,
    effective_until,
    change_note,
    commit_usage_snapshot,
    llm_requests_snapshot,
    notification_credits_snapshot,
    is_new_plan_team_plan
  )
  VALUES (
    OLD.id,
    OLD.plan_key::TEXT, -- ENUM 타입을 TEXT로 변환하여 저장
    NEW.plan_key::TEXT,
    OLD.plan_label,     -- MVP 단계에서는 직접 사용
    NEW.plan_label,
    OLD.monthly_price_usd,
    NEW.monthly_price_usd,
    OLD.is_trial_active,
    COALESCE(current_setting('comfort_commit.actor_id', TRUE), 'system_trigger'), -- 트리거 호출자 감지
    'plan_change_via_trigger',
    OLD.current_period_ends_at,
    NEW.current_period_started_at,
    'Plan changed from ' || OLD.plan_key::TEXT || ' to ' || NEW.plan_key::TEXT || ' via trigger.',
    NULL, NULL, NULL, -- 추후 commit/LLM/알림 사용량 snapshot 추가 예정
    (SELECT pc.is_team_plan FROM plan_catalog pc WHERE pc.plan_key = NEW.plan_key::TEXT LIMIT 1)
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION insert_user_plan_history_trigger_function() IS 'user_plan.plan_key 변경 시 user_plan_history에 자동으로 이력을 기록하는 트리거 함수입니다. (세부 구현은 plan_catalog 연동 및 애플리케이션 로직에 따라 달라질 수 있습니다.)';


-- -------------------------------------------------------------------------------------
-- II. 공통 ENUM 타입 (Common ENUM Types)
-- -------------------------------------------------------------------------------------

-- 설명: 사용자 계정 유형 (개인, 팀, 조직)을 명확하게 분리합니다.
-- 사용 위치: user_info.account_type (01_user_info.sql)
CREATE TYPE user_account_type_enum AS ENUM (
    'personal',     -- 개인 사용자 (기본)
    'team',         -- 팀 단위 사용자 (소규모 협업)
    'organization'  -- 조직 또는 엔터프라이즈 사용자
);
COMMENT ON TYPE user_account_type_enum IS '사용자 계정의 유형을 정의합니다 (예: 개인, 팀, 조직).';


-- 설명: 시스템에서 제공하는 요금제의 내부 식별 키 값 (ENUM)
-- 사용 위치: user_plan.plan_key, user_plan_history.old_plan_key/new_plan_key
-- 주의: 실제 라벨은 plan_label TEXT 컬럼 또는 별도 plan_catalog 테이블에서 관리
CREATE TYPE plan_key_enum AS ENUM (
    'free',                     -- 무료 플랜
    'basic_monthly',           -- 개인 월간 요금제
    'premium_monthly',         -- 개인 월간 프리미엄
    'basic_annual',            -- 연간 요금제 (개인)
    'premium_annual',          -- 연간 프리미엄 요금제
    'team_basic_monthly',      -- 팀 월간 기본 플랜
    'team_premium_monthly',    -- 팀 월간 프리미엄 플랜
    'enterprise_custom',       -- 맞춤형 B2B 플랜
    'trial_premium_monthly',   -- 프리미엄 체험판 (월 단위)
    'trial_basic_monthly'      -- 베이직 체험판 (월 단위)
);
COMMENT ON TYPE plan_key_enum IS '시스템에서 제공하는 요금제의 내부 식별 키 값들의 집합입니다.';


-- 설명: 사용자에게 부여된 보상의 상태
-- 사용 위치: user_reward_log.reward_status
-- 사용 목적: 보상 수령, 사용, 만료, 취소 등의 상태 구분
CREATE TYPE reward_status_enum AS ENUM (
    'active',         -- 사용 가능
    'used',           -- 사용됨
    'expired',        -- 만료됨
    'revoked',        -- 취소됨 (관리자 또는 정책)
    'pending_claim'   -- 사용자 수령 대기 상태
);
COMMENT ON TYPE reward_status_enum IS '사용자에게 지급된 보상의 상태를 나타내는 값들의 집합입니다.';


-- 설명: 사용자 계정 탈퇴 요청 처리 상태 ENUM
-- 사용 위치: user_deletion_request.status
-- 처리 단계 및 오류 상황을 모두 포함
CREATE TYPE deletion_request_status_enum AS ENUM (
    'pending_user_confirmation',   -- 사용자 이메일 확인 대기
    'pending_processing',          -- 시스템 또는 관리자의 처리 대기
    'processing_in_progress',      -- 처리 진행 중
    'completed_data_deleted',      -- 전체 삭제 완료
    'completed_data_anonymized',  -- 익명화 처리 완료
    'rejected_by_admin',           -- 관리자에 의해 거부됨
    'cancelled_by_user',           -- 사용자가 요청 철회
    'error_during_processing',     -- 처리 중 오류 발생
    'retention_period_active'      -- 법적 보관 기간 유지 중 (삭제 불가 상태)
);
COMMENT ON TYPE deletion_request_status_enum IS '사용자 계정 탈퇴 요청의 처리 상태를 나타내는 값들의 집합입니다.';

-- =====================================================================================
-- ✅ 최종 출력: 실행 완료 여부 확인 메시지
-- =====================================================================================
SELECT 'Common functions and ENUM types created/updated successfully.' AS status;
