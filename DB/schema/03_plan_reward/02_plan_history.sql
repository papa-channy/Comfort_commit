-- =====================================================================================
-- 파일: 02_user_plan_history.sql
-- 모듈: 03_plan_and_reward_module (요금제 및 보상 모듈)
-- 설명: 사용자의 요금제 변경 이력을 기록합니다.
-- 대상 DB: PostgreSQL Primary RDB (사용자 구독 이력 데이터)
-- 파티셔닝: 고려 가능 (`changed_at` 기준, 이력 데이터가 매우 많아질 경우 - 스케일업 시)
-- MVP 중점사항: 요금제 변경 전후 정보, 변경 주체/경로 기록, 필수 인덱스. ON DELETE 정책 명확화.
-- 스케일업 고려사항: RLS 적용, 파티셔닝, 분석용 스냅샷 컬럼의 데이터 소스 명확화 및 자동화.
-- 개인정보보호: 사용자 탈퇴 시 uuid는 NULL로 설정되어 이력은 익명으로 보존.
-- =====================================================================================

-- 사용자 요금제 변경 이력 테이블
CREATE TABLE user_plan_history (
  id SERIAL PRIMARY KEY,                                  -- 내부 자동 증가 ID

  -- 🆔 사용자 식별
  uuid UUID REFERENCES user_info(uuid) ON DELETE SET NULL,
  -- 요금제 변경 대상 사용자. 사용자 탈퇴 시 이력은 남기되, 사용자 식별자는 NULL로 설정하여 익명화.

  -- 🔁 변경 요금제 정보
  old_plan_key TEXT,                                      -- 변경 전 요금제의 내부 식별 키 (user_plan.plan_key의 ENUM 값을 TEXT로 저장)
  new_plan_key TEXT,                                      -- 변경 후 요금제의 내부 식별 키 (user_plan.plan_key의 ENUM 값을 TEXT로 저장)
  old_plan_label TEXT,                                    -- 변경 전 요금제의 UI 표시용 이름
  new_plan_label TEXT,                                    -- 변경 후 요금제의 UI 표시용 이름

  -- 💳 과금 및 조건 변화
  old_price_usd NUMERIC(8,2),                             -- 이전 요금제의 월 요금 (또는 해당 시점의 요금)
  new_price_usd NUMERIC(8,2),                             -- 변경 후 요금제의 월 요금
  was_trial BOOLEAN DEFAULT FALSE,                        -- 이 변경이 트라이얼 기간 종료 후 유료 플랜으로의 전환이었는지 여부

  -- 📅 적용 기간 및 종료일 (이 히스토리 레코드가 나타내는 특정 요금제의 유효 기간)
  effective_from TIMESTAMP,                               -- 이 히스토리 레코드(new_plan_key)가 적용되기 시작한 시점
  effective_until TIMESTAMP,                              -- 이 히스토리 레코드(new_plan_key)의 적용이 종료된 시점

  -- 🔧 변경 메타 정보
  changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,         -- 이 히스토리 레코드가 생성된 시각 (즉, 요금제 변경이 발생한 시점)
  changed_by TEXT,                                        -- 변경 주체 (예: 'user_self_service', 'admin_manual_update', 'system_auto_upgrade', 'trigger_plan_change')
  source_of_change TEXT,                                  -- 변경 유입 경로 또는 원인 (예: 'user_request_upgrade', 'promotion_code_XYZ', 'trial_conversion')
  change_note TEXT,                                       -- 변경에 대한 추가 설명 또는 관리자 메모

  -- 📊 분석용 스냅샷 (MVP에서는 컬럼 정의만 유지, 실제 구현 시 데이터 소스 및 필요성 재검토)
  commit_usage_snapshot INT,                        -- 변경 시점의 해당 월 커밋 사용량 (컬럼명 확정)
  -- describe_usage_snapshot INT, (llm_requests_snapshot으로 대체 또는 제거 고려)
  llm_requests_snapshot INT,                          -- 변경 시점의 해당 월 LLM 요청 수
  -- kakao_noti_remaining_snapshot INT, (notification_credits_snapshot 등으로 일반화 또는 제거 고려)
  notification_credits_snapshot INT,                  -- 변경 시점의 알림 크레딧 잔여량
  is_new_plan_team_plan BOOLEAN DEFAULT FALSE             -- 변경된 '새' 요금제가 팀 요금제인지 여부 플래그

  -- updated_at 컬럼은 히스토리성 데이터이므로 불필요.
);

COMMENT ON TABLE user_plan_history IS '사용자의 요금제 변경 이력을 시간 순으로 기록합니다. 각 레코드는 하나의 요금제 변경 이벤트를 나타냅니다.';
COMMENT ON COLUMN user_plan_history.uuid IS '요금제가 변경된 사용자의 UUID (user_info.uuid 참조)입니다. 사용자 탈퇴 시 NULL로 설정됩니다.';
COMMENT ON COLUMN user_plan_history.old_plan_key IS '변경 전 사용자의 요금제 식별 키입니다 (user_plan.plan_key의 ENUM 값을 TEXT로 저장).';
COMMENT ON COLUMN user_plan_history.new_plan_key IS '변경 후 사용자의 새로운 요금제 식별 키입니다 (user_plan.plan_key의 ENUM 값을 TEXT로 저장).';
COMMENT ON COLUMN user_plan_history.effective_from IS '새로운 요금제가 효력을 발생하기 시작한 시점입니다.';
COMMENT ON COLUMN user_plan_history.effective_until IS '해당 이력으로 기록된 요금제의 적용이 종료된 (다음 변경이 발생하기 직전의) 시점입니다.';
COMMENT ON COLUMN user_plan_history.changed_at IS '이 요금제 변경 이력 레코드가 생성된, 즉 요금제 변경이 실제 발생한 시점입니다.';
COMMENT ON COLUMN user_plan_history.changed_by IS '요금제 변경을 실행한 주체입니다 (예: 사용자 본인, 관리자, 시스템 자동 변경).';
COMMENT ON COLUMN user_plan_history.commit_usage_snapshot IS '요금제 변경 시점의 해당 월 누적 커밋 사용량 스냅샷입니다.';

-- user_plan_history 테이블 인덱스
CREATE INDEX idx_user_plan_history_uuid_changed_at ON user_plan_history(uuid, changed_at DESC) WHERE uuid IS NOT NULL; -- 특정 활성 사용자의 요금제 변경 이력 시간순 조회
CREATE INDEX idx_user_plan_history_new_plan_key ON user_plan_history(new_plan_key); -- 특정 요금제로 변경한 이력 조회
CREATE INDEX idx_user_plan_history_changed_by ON user_plan_history(changed_by); -- 특정 주체에 의한 변경 이력 조회
CREATE INDEX idx_user_plan_history_was_trial ON user_plan_history(was_trial) WHERE was_trial = TRUE; -- 트라이얼 전환 이력 조회
CREATE INDEX idx_user_plan_history_is_new_team_plan ON user_plan_history(is_new_plan_team_plan) WHERE is_new_plan_team_plan = TRUE;

-- 요금제 변경(plan_key) 시 이 테이블에 이력을 기록하는 트리거는 user_plan.sql 파일에 정의되어 있습니다.
-- (참고: insert_user_plan_history() 함수는 user_plan_history 테이블의 최종 컬럼 구조에 맞게 조정되어야 하며,
--  스냅샷 컬럼 값들은 해당 함수 내에서 OLD 레코드나 다른 집계 테이블로부터 가져오는 로직이 필요합니다.)