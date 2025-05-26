-- =====================================================================================
-- 파일: 02_user_plan_history.sql
-- 모듈: 03_plan_and_reward_module (요금제 및 보상 모듈)
-- 설명: 사용자의 요금제 변경 이력을 기록합니다.
-- 대상 DB: PostgreSQL Primary RDB (사용자 구독 이력 데이터)
-- 파티셔닝: 고려 가능 (`changed_at` 기준, 이력 데이터가 매우 많아질 경우 - 스케일업 시)
-- MVP 중점사항: 요금제 변경 전후 정보, 변경 주체/경로 기록, 필수 인덱스. ON DELETE 정책 명확화. 스냅샷 컬럼은 정의하되, 값은 MVP에서 수동 또는 단순 기록, 스케일업 시 자동 집계.
-- 스케일업 고려사항: RLS 적용, 파티셔닝, 분석용 스냅샷 컬럼의 데이터 자동 집계(Materialized View 또는 배치 작업), changed_by/source_of_change ENUM 또는 마스터 테이블화.
-- 개인정보보호: 사용자 탈퇴 시 id는 NULL로 설정되어 이력은 익명으로 보존.
-- =====================================================================================

-- 사용자 요금제 변경 이력 테이블
CREATE TABLE user_plan_history (
  uuid SERIAL PRIMARY KEY,                                  -- 내부 자동 증가 uuid

  -- 🆔 사용자 식별
  id id REFERENCES user_info(id) ON DELETE SET NULL,
  -- 요금제 변경 대상 사용자. 사용자 탈퇴 시 이력은 남기되, 사용자 식별자는 NULL로 설정하여 익명화.

  -- 🔁 변경 요금제 정보
  old_plan_key TEXT,                                      -- 변경 전 요금제의 내부 식별 키 (user_plan.plan_key의 ENUM 값을 TEXT로 저장)
  new_plan_key TEXT,                                      -- 변경 후 요금제의 내부 식별 키 (user_plan.plan_key의 ENUM 값을 TEXT로 저장)
  old_plan_label TEXT,                                    -- 변경 전 요금제의 UI 표시용 이름 (user_plan.plan_label 또는 plan_catalog 참조)
  new_plan_label TEXT,                                    -- 변경 후 요금제의 UI 표시용 이름 (user_plan.plan_label 또는 plan_catalog 참조)

  -- 💳 과금 및 조건 변화
  old_price_usd NUMERIC(8,2),                             -- 이전 요금제의 월 요금 (또는 해당 시점의 요금)
  new_price_usd NUMERIC(8,2),                             -- 변경 후 요금제의 월 요금
  was_trial BOOLEAN DEFAULT FALSE,                        -- 이 변경이 트라이얼 기간 종료 후 유료 플랜으로의 전환이었는지 여부

  -- 📅 적용 기간 및 종료일 (이 히스토리 레코드가 나타내는 특정 요금제의 유효 기간)
  effective_from TIMESTAMP,                               -- 이 히스토리 레코드(new_plan_key)가 적용되기 시작한 시점 (일반적으로 OLD.current_period_ends_at 또는 changed_at)
  effective_until TIMESTAMP,                              -- 이 히스토리 레코드(new_plan_key)의 적용이 종료된 시점 (다음 변경 발생 시 NEW.current_period_started_at 또는 해당 플랜의 실제 종료일)

  -- 🔧 변경 메타 정보
  changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,-- 이 히스토리 레코드가 생성된 시각 (즉, 요금제 변경이 발생한 시점)
  changed_by TEXT,                                        -- 변경 주체 (예: 'user_self_service', 'admin_manual_update', 'system_auto_upgrade', 'trigger_plan_change'). (스케일업 시: ENUM 또는 별도 user_role 테이블 FK 고려)
  source_of_change TEXT,                                  -- 변경 유입 경로 또는 원인 (예: 'user_request_upgrade', 'promotion_code_XYZ', 'trial_conversion', 'billing_failure_downgrade'). (스케일업 시: ENUM 또는 별도 테이블 FK 고려)
  change_note TEXT,                                       -- 변경에 대한 추가 설명 또는 관리자 메모

  -- 📊 분석용 스냅샷 (MVP에서는 값 기록을 위한 컬럼 정의만. 실제 값은 트리거 또는 앱 로직에서 해당 시점 데이터로 채워야 함)
  commit_usage_snapshot INT,                              -- 변경 시점의 해당 월 누적 커밋 사용량 스냅샷
  llm_requests_snapshot INT,                              -- 변경 시점의 해당 월 누적 LLM 요청 수 스냅샷
  notification_credits_snapshot INT,                      -- 변경 시점의 알림 크레딧 잔여량 스냅샷
  is_new_plan_team_plan BOOLEAN DEFAULT FALSE             -- 변경된 '새' 요금제가 팀 요금제인지 여부 플래그 (new_plan_key 기반으로 판단 가능)

  -- updated_at 컬럼은 히스토리성 데이터이므로 일반적으로 불필요.
);

COMMENT ON TABLE user_plan_history IS '사용자의 요금제 변경 이력을 시간 순으로 기록합니다. 각 레코드는 하나의 요금제 변경 이벤트를 나타냅니다.';
COMMENT ON COLUMN user_plan_history.uuid IS '요금제 변경 이력 레코드의 내부 자동 증가 uuid입니다.';
COMMENT ON COLUMN user_plan_history.id IS '요금제가 변경된 사용자의 id (user_info.id 참조)입니다. 사용자 탈퇴 시 NULL로 설정됩니다.';
COMMENT ON COLUMN user_plan_history.old_plan_key IS '변경 전 사용자의 요금제 식별 키입니다 (user_plan.plan_key의 ENUM 값을 TEXT로 저장하여 유연성 확보).';
COMMENT ON COLUMN user_plan_history.new_plan_key IS '변경 후 사용자의 새로운 요금제 식별 키입니다 (user_plan.plan_key의 ENUM 값을 TEXT로 저장).';
COMMENT ON COLUMN user_plan_history.old_plan_label IS '변경 전 요금제의 UI 표시용 이름입니다 (plan_catalog 또는 user_plan 테이블 참조).';
COMMENT ON COLUMN user_plan_history.new_plan_label IS '변경 후 요금제의 UI 표시용 이름입니다 (plan_catalog 또는 user_plan 테이블 참조).';
COMMENT ON COLUMN user_plan_history.old_price_usd IS '변경 전 요금제의 월간 USD 가격입니다.';
COMMENT ON COLUMN user_plan_history.new_price_usd IS '변경 후 요금제의 월간 USD 가격입니다.';
COMMENT ON COLUMN user_plan_history.was_trial IS '이 변경이 평가판(trial) 상태에서 정식 요금제로 전환된 것인지 여부를 나타냅니다.';
COMMENT ON COLUMN user_plan_history.effective_from IS '새로운 요금제가 효력을 발생하기 시작한 시점입니다. 일반적으로 이전 요금제의 종료 시점 또는 변경이 기록된 시점입니다.';
COMMENT ON COLUMN user_plan_history.effective_until IS '해당 이력으로 기록된 요금제의 적용이 종료된 (다음 변경이 발생하기 직전의) 시점입니다. 마지막 이력의 경우 NULL일 수 있습니다.';
COMMENT ON COLUMN user_plan_history.changed_at IS '이 요금제 변경 이력 레코드가 생성된, 즉 요금제 변경이 실제 발생한 시점입니다.';
COMMENT ON COLUMN user_plan_history.changed_by IS '요금제 변경을 실행한 주체입니다 (예: 사용자 본인, 관리자, 시스템 자동 변경). 스케일업 시 ENUM 또는 별도 역할 테이블 FK 사용을 고려합니다.';
COMMENT ON COLUMN user_plan_history.source_of_change IS '요금제 변경을 유발한 원인 또는 경로입니다 (예: 프로모션 코드 사용, 체험판 만료).';
COMMENT ON COLUMN user_plan_history.change_note IS '요금제 변경과 관련된 추가적인 설명이나 관리자 메모입니다.';
COMMENT ON COLUMN user_plan_history.commit_usage_snapshot IS '요금제 변경 시점의 해당 월 누적 커밋 사용량 스냅샷입니다. 분석 목적으로 트리거나 애플리케이션 로직에서 값을 채웁니다.';
COMMENT ON COLUMN user_plan_history.llm_requests_snapshot IS '요금제 변경 시점의 해당 월 누적 LLM 요청 수 스냅샷입니다.';
COMMENT ON COLUMN user_plan_history.notification_credits_snapshot IS '요금제 변경 시점의 알림 크레딧 잔여량 스냅샷입니다.';
COMMENT ON COLUMN user_plan_history.is_new_plan_team_plan IS '변경된 새 요금제가 팀 또는 조직 관련 요금제인지 여부를 나타내는 플래그입니다.';


-- user_plan_history 테이블 인덱스
CREATE INDEX uuidx_user_plan_history_id_changed_at ON user_plan_history(id, changed_at DESC) WHERE id IS NOT NULL; -- 특정 활성 사용자의 요금제 변경 이력 시간순 조회
CREATE INDEX uuidx_user_plan_history_new_plan_key ON user_plan_history(new_plan_key); -- 특정 요금제로 변경한 이력 조회
CREATE INDEX uuidx_user_plan_history_changed_by ON user_plan_history(changed_by); -- 특정 주체에 의한 변경 이력 조회
CREATE INDEX uuidx_user_plan_history_was_trial ON user_plan_history(was_trial) WHERE was_trial = TRUE; -- 트라이얼 전환 이력 조회
CREATE INDEX uuidx_user_plan_history_is_new_team_plan ON user_plan_history(is_new_plan_team_plan) WHERE is_new_plan_team_plan = TRUE; -- 팀 요금제 변경 이력 조회

-- 요금제 변경(plan_key) 시 이 테이블에 이력을 기록하는 트리거는 user_plan.sql 파일에 정의되어 있습니다.
-- (참고: insert_user_plan_history_trigger_function() 함수는 user_plan_history 테이블의 최종 컬럼 구조에 맞게 조정되어야 하며,
--  스냅샷 컬럼 값들은 해당 함수 내에서 OLD 레코드의 값이나 다른 집계 테이블로부터 가져오는 로직이 필요합니다.
--  MVP 단계에서는 스냅샷 값들이 NULL일 수 있음을 인지하고, 애플리케이션에서 필요한 경우 채워 넣도록 합니다.)