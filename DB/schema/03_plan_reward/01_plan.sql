-- =====================================================================================
-- 파일: 01_user_plan.sql
-- 모듈: 03_plan_and_reward_module (요금제 및 보상 모듈)
-- 설명: 사용자의 현재 요금제 정보, 관련 사용량 한도, 기능 접근 권한 등을 관리합니다.
-- 대상 DB: PostgreSQL Primary RDB (사용자 구독 및 권한 데이터)
-- 파티셔닝: 없음 (사용자당 1개의 로우)
-- MVP 중점사항: 핵심 요금제 정보, ENUM 타입 사용, 기능 플래그 명시적 컬럼 유지, 필수 인덱스, 이력 기록 트리거.
-- 스케일업 고려사항: RLS 적용, 기능 플래그 JSONB로 전환 또는 별도 매핑 테이블 사용, plan_catalog 마스터 테이블과의 연동 강화, 동적 요금제 확장을 위한 Lookup Table 전환, 데이터 보관 정책 자동화 연동.
-- =====================================================================================

-- 요금제 키 ENUM 타입 정의
-- (향후 00_common_functions_and_types.sql 파일로 통합 예정)
CREATE TYPE plan_key_enum AS ENUM (
    'free',
    'basic_monthly',
    'premium_monthly',
    'basic_annual',
    'premium_annual',
    'team_basic_monthly',
    'team_premium_monthly',
    'enterprise_custom',
    'trial_premium' -- 예시: 프리미엄 기능 체험판
);
COMMENT ON TYPE plan_key_enum IS '시스템에서 제공하는 요금제의 내부 식별 키 값들의 집합입니다.';

-- 사용자 요금제 정보 테이블
CREATE TABLE user_plan (
  uuid UUID PRIMARY KEY REFERENCES user_info(uuid) ON DELETE CASCADE,
  -- user_info 테이블의 uuid를 참조하며, 사용자 탈퇴 시 관련 요금제 정보도 함께 삭제됩니다.

  -- 🧾 요금제 구분
  plan_key plan_key_enum NOT NULL DEFAULT 'free',          -- 시스템 내부 요금제 식별 키 (ENUM 타입 적용)
  plan_label TEXT,                                        -- UI 등에 표시될 사용자를 위한 요금제 이름 (예: '개인 베이직 (월간)', '팀 프리미엄'). plan_catalog 테이블에서 관리될 수 있음.

  -- 📊 사용량 한도 (이 테이블은 "한도"만 정의, 실제 사용량은 로그 테이블 집계 또는 Redis 카운터 등으로 판단)
  max_commits_per_day INT,                                -- 일일 커밋 생성 최대 횟수 (Comfort Commit 기능 사용 횟수)
  max_commits_per_month INT,                              -- 월별 커밋 생성 최대 횟수
  max_llm_requests_per_day INT,                           -- 일일 LLM 요청 최대 횟수 (구체적인 기능별 한도는 plan_features JSONB 등으로 관리 가능)
  max_analyzed_repos INT,                                 -- 동시에 분석/연동 가능한 최대 저장소 수

  -- 💬 알림/연동 채널 권한 및 사용량 (일부 크레딧 기반 기능)
  allowed_notification_channels TEXT[],                   -- 사용 가능한 알림 채널 목록 (예: ARRAY['email', 'slack'])
  notification_credits_monthly INT DEFAULT 0,             -- 특정 채널(예: 유료 SMS) 사용을 위한 월간 크레딧 (0이면 무제한 또는 사용 불가)
  slack_integration_enabled BOOLEAN DEFAULT FALSE,        -- Slack 연동 기능 전체 활성화 여부

  -- 📺 UX 및 광고 관련 설정
  ad_display_enabled BOOLEAN DEFAULT TRUE,                -- 서비스 내 광고 레이어 노출 여부 (주로 무료 플랜)
  priority_support_enabled BOOLEAN DEFAULT FALSE,         -- 우선 고객 지원 채널 접근 가능 여부

  -- 💾 데이터 저장 / 리포트 기능 권한
  commit_history_retention_months INT DEFAULT 1,          -- Comfort Commit을 통해 생성/관리된 커밋 이력 보존 기간 (개월 단위)
  data_export_enabled BOOLEAN DEFAULT FALSE,              -- 사용자 데이터(예: 커밋 이력, 분석 결과) 내보내기 기능 사용 가능 여부
  advanced_analytics_access BOOLEAN DEFAULT FALSE,        -- 고급 분석/리포트 기능 접근 권한

  -- 🧠 LLM 및 분석 기능 관련 설정
  allowed_llm_models TEXT[] DEFAULT ARRAY['default_model'],-- 사용 가능한 LLM 모델 목록 (또는 'all', 또는 특정 모델 그룹)
  custom_prompt_enabled BOOLEAN DEFAULT FALSE,            -- 사용자 정의 프롬프트 사용 가능 여부
  analysis_depth_level TEXT DEFAULT 'standard',           -- 코드 분석 깊이 수준 (스케일업 시: ENUM 고려: 'quick', 'standard', 'deep')

  -- 🔒 데이터 보존 정책 (llm_request_log 원문 등 민감 데이터에 대한 보존 기간)
  pii_data_retention_days INT DEFAULT 30,                 -- 개인 식별 정보 포함 가능성이 있는 데이터(예: LLM 프롬프트/응답 원문)의 보존 기간 (일 단위). user_info.is_active=false 시점부터 카운트 또는 별도 정책.

  -- 👥 팀 협업 기능 (팀/조직 플랜의 경우)
  max_team_members INT,                                   -- 해당 요금제에서 허용하는 최대 팀 멤버 수 (팀 플랜용)
  team_shared_dashboard_enabled BOOLEAN DEFAULT FALSE,    -- 팀 공유 대시보드 기능 사용 가능 여부

  -- 💵 요금 정보
  monthly_price_usd NUMERIC(8,2),                         -- 월 요금 (USD 기준, 소수점 2자리)
  annual_price_usd NUMERIC(8,2),                          -- 연 요금 (USD 기준, 선택적)
  trial_duration_days INT DEFAULT 0,                      -- 무료 체험판 제공 기간 (일 단위)

  -- 🕒 상태 정보
  subscription_status TEXT DEFAULT 'active',              -- 구독 상태 (스케일업 시: ENUM 고려: 'active', 'trialing', 'past_due', 'payment_failed', 'cancelled', 'expired', 'pending_upgrade')
  is_trial_active BOOLEAN DEFAULT FALSE,                  -- 현재 체험판 활성 여부 (subscription_status와 연계)
  current_period_started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, -- 현재 구독(또는 체험판) 기간 시작 시각
  current_period_ends_at TIMESTAMP,                       -- 현재 구독(또는 체험판) 기간 종료 시각 (갱신 필요 시점 또는 다음 결제일)
  cancelled_at TIMESTAMP,                                 -- 구독 취소 요청 시각 (취소된 경우)
  grace_period_ends_at TIMESTAMP,                         -- 결제 실패 또는 구독 만료 후 유예 기간 종료 시각
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP -- 이 요금제 정보가 마지막으로 수정된 시각 (trg_set_updated_at_user_plan 트리거로 자동 관리)
);

COMMENT ON TABLE user_plan IS '사용자의 현재 요금제 및 관련 사용량 한도, 기능 접근 권한 등을 저장합니다.';
COMMENT ON COLUMN user_plan.uuid IS 'user_info 테이블의 사용자 UUID를 참조하는 기본 키입니다.';
COMMENT ON COLUMN user_plan.plan_key IS '시스템 내부에서 사용되는 요금제의 고유 식별 키입니다 (ENUM 타입). 실제 정책은 plan_catalog 테이블 또는 설정 파일에서 관리될 수 있습니다.';
COMMENT ON COLUMN user_plan.max_llm_requests_per_day IS '하루에 허용되는 LLM API 총 요청 횟수 한도입니다. 초과 시 제한 또는 추가 과금이 발생할 수 있습니다.';
COMMENT ON COLUMN user_plan.pii_data_retention_days IS '개인 식별 정보 포함 가능성이 있는 데이터(예: LLM 로그 원문)의 보존 기간(일)입니다. 이 기간 이후에는 마스킹, 삭제 또는 익명화 처리됩니다.';
COMMENT ON COLUMN user_plan.subscription_status IS '현재 사용자의 구독 상태를 나타냅니다 (예: active, trialing, cancelled). 스케일업 시 ENUM 타입 사용을 고려합니다.';
COMMENT ON COLUMN user_plan.current_period_ends_at IS '현재 구독 또는 체험 기간이 종료되는 시각으로, 다음 결제 또는 상태 변경의 기준이 됩니다.';
COMMENT ON COLUMN user_plan.updated_at IS '이 사용자 요금제 정보가 마지막으로 변경된 시각입니다.';

-- user_plan 테이블 인덱스
CREATE INDEX idx_user_plan_uuid_plan_key ON user_plan(uuid, plan_key); -- 특정 사용자의 특정 요금제 정보 빠르게 접근
CREATE INDEX idx_user_plan_expiry ON user_plan(current_period_ends_at); -- 구독 만료 예정 사용자 조회
CREATE INDEX idx_user_plan_status ON user_plan(subscription_status); -- 특정 구독 상태의 사용자 필터링

-- updated_at 컬럼 자동 갱신 트리거
-- (참고: set_updated_at() 함수는 '00_common_functions_and_types.sql' 파일에 최종적으로 통합 정의될 예정)
CREATE TRIGGER trg_set_updated_at_user_plan
BEFORE UPDATE ON user_plan
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 요금제 변경(plan_key) 시 user_plan_history 테이블에 이력 자동 기록 트리거
-- (참고: insert_user_plan_history() 함수는 '00_common_functions_and_types.sql' 파일에 최종적으로 통합 정의될 예정이며,
--  user_plan_history 테이블의 최종 컬럼 구조 및 plan_catalog 와의 연동을 고려하여 함수 내용 조정 필요)
CREATE TRIGGER trg_log_user_plan_change
AFTER UPDATE OF plan_key ON user_plan
FOR EACH ROW
WHEN (OLD.plan_key IS DISTINCT FROM NEW.plan_key) -- plan_key가 실제로 변경되었을 때만 실행
EXECUTE FUNCTION insert_user_plan_history();

-- 스케일업 고려사항 주석:
-- COMMENT ON TABLE user_plan IS '(스케일업 시: 다수의 기능 플래그(예: slack_integration_enabled, data_export_enabled 등)는 plan_features JSONB 형태로 통합 관리하거나, plan_feature_matrix(plan_key, feature_key, value)와 같은 별도 매핑 테이블로 분리하여 유연성 및 확장성 확보 고려. 또한, plan_label 및 가격 정보 등은 plan_catalog 마스터 테이블에서 조회하여 중복 최소화)';