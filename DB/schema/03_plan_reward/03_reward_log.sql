-- =====================================================================================
-- 파일: 03_user_reward_log.sql
-- 모듈: 03_plan_and_reward_module (요금제 및 보상 모듈)
-- 설명: 사용자에게 지급된 각종 보상(리워드)에 대한 로그를 기록하고 관리합니다.
-- 대상 DB: PostgreSQL Primary RDB (사용자 보상 이력 데이터)
-- 파티셔닝: 고려 가능 (`created_at` 기준, 보상 지급/사용 이벤트가 매우 많을 경우 - 스케일업 시)
-- MVP 중점사항: 핵심 보상 정보, 공통 ENUM 타입 참조, 필수 인덱스, 만료 보상 처리 함수 연동 고려.
-- 스케일업 고려사항: RLS 적용, 파티셔닝, trigger_type/reward_type 마스터 테이블 분리, 보상 유형별 상세 분석 기능, 누적 합계 캐싱.
-- 개인정보보호: 사용자 탈퇴 시 receiver_id는 NULL로 설정되어 보상 로그는 익명으로 보존 (또는 CASCADE 유지 후 별도 익명화된 집계 테이블 활용).
-- =====================================================================================

-- 사용자 보상 로그 테이블
CREATE TABLE user_reward_log (
  uuid BIGSERIAL PRIMARY KEY,                               -- 보상 로그 고유 uuid (대량 이벤트 대응을 위해 BIGSERIAL 사용)

  -- 🎯 보상 수신자
  receiver_id id NOT NULL REFERENCES user_info(id) ON DELETE SET NULL,
  -- 리워드를 받는 사용자. 사용자 탈퇴 시 이 로그는 남기되, 사용자 식별자는 NULL로 설정하여 익명화.

  -- 🔄 트리거 정보 (어떤 행동/조건으로 보상이 발생했는지)
  trigger_type TEXT NOT NULL,                             -- 보상 트리거 유형 (예: 'referral_signup_completed', 'daily_mission_achieved', 'promotional_code_applied'). (스케일업 시: ENUM 또는 별도 reward_trigger_master 테이블 참조 고려)
  
  -- 🎁 보상 정보
  reward_type TEXT NOT NULL,                              -- 보상 내용 유형 (예: 'notification_credit', 'ad_free_duration', 'feature_unlock_ticket'). (스케일업 시: ENUM 또는 별도 reward_item_master 테이블 참조 고려)
  reward_value NUMERIC(12,2),                             -- 보상의 양 또는 정도 (예: 10.00 (크레딧 10개), 24.00 (24시간 광고 제거)). 소수점 표현 가능.
  reward_unit TEXT,                                       -- 보상 값의 단위 (예: 'credits', 'hours', 'days', 'tickets', 'percentage_discount', 'fixed_amount_discount_usd')

  -- 🔗 연관 유저/이벤트
  source_user_id id REFERENCES user_info(id) ON DELETE SET NULL, -- 이 보상 발생에 기여한 다른 사용자 (예: 추천인). 자기 자신이 source가 될 수도 있음.
  related_event_uuidentifier TEXT,                          -- 연관된 이벤트, 프로모션 코드, 캠페인 uuid 등 외부 식별자 (예: 'REF_CODE_XYZ123', 'SPRING_PROMO_2025', 'MISSION_uuid_007')
  
  -- 📆 상태 및 유효기간
  reward_status reward_status_enum NOT NULL DEFAULT 'active', -- 보상 상태 (00_common_functions_and_types.sql 정의된 ENUM 타입 적용)
  reward_expire_at TIMESTAMP,                             -- 보상 유효 기간 만료 시각 (NULL이면 영구 또는 별도 정책 따름)

  -- 🗒️ 메모 및 기록
  memo_for_admin TEXT,                                    -- 내부 운영 및 관리자를 위한 메모

  -- 🕒 시각 정보
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, -- 이 보상 로그가 생성된 시각 (즉, 보상이 지급된 시점)
  used_at TIMESTAMP,                                      -- 보상이 실제로 사용 처리된 시각 (사용된 경우에만 기록)
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP -- 이 보상 로그 레코드의 정보(주로 상태)가 마지막으로 수정된 시각
);

COMMENT ON TABLE user_reward_log IS '사용자에게 지급된 다양한 유형의 보상(리워드)에 대한 상세 이력을 기록하고 관리합니다.';
COMMENT ON COLUMN user_reward_log.uuid IS '보상 로그 레코드의 내부 자동 증가 uuid입니다.';
COMMENT ON COLUMN user_reward_log.receiver_id IS '보상을 지급받은 사용자의 id입니다. 사용자 탈퇴 시 NULL로 설정되어 로그는 익명으로 보존됩니다.';
COMMENT ON COLUMN user_reward_log.trigger_type IS '어떤 행동이나 조건 충족으로 인해 이 보상이 지급되었는지 나타내는 유형입니다. 스케일업 시 ENUM 또는 마스터 테이블 참조를 고려합니다.';
COMMENT ON COLUMN user_reward_log.reward_type IS '지급된 보상의 구체적인 종류를 나타냅니다. 스케일업 시 ENUM 또는 마스터 테이블 참조를 고려합니다.';
COMMENT ON COLUMN user_reward_log.reward_value IS '지급된 보상의 수량 또는 정도를 나타냅니다. reward_unit과 함께 해석됩니다. NUMERIC(12,2)로 정의하여 다양한 값 표현 가능.';
COMMENT ON COLUMN user_reward_log.reward_unit IS 'reward_value의 단위를 나타냅니다 (예: 시간, 횟수, 금액 등).';
COMMENT ON COLUMN user_reward_log.source_user_id IS '이 보상 지급을 유발한 (또는 관련된) 다른 사용자의 id입니다 (예: 추천인).';
COMMENT ON COLUMN user_reward_log.related_event_uuidentifier IS '이 보상과 관련된 특정 이벤트, 프로모션, 캠페인 등의 외부 식별자입니다.';
COMMENT ON COLUMN user_reward_log.reward_status IS '현재 보상의 상태를 나타냅니다 (00_common_functions_and_types.sql 정의된 reward_status_enum 값: 활성, 사용됨, 만료됨 등).';
COMMENT ON COLUMN user_reward_log.reward_expire_at IS '이 보상이 만료되어 더 이상 사용할 수 없게 되는 시각입니다. NULL인 경우 별도의 만료 정책이 없음을 의미할 수 있습니다.';
COMMENT ON COLUMN user_reward_log.memo_for_admin IS '이 보상 지급 또는 상태 변경에 대한 관리자용 내부 메모입니다.';
COMMENT ON COLUMN user_reward_log.created_at IS '이 보상 레코드가 데이터베이스에 생성된, 즉 보상이 지급된 시점입니다.';
COMMENT ON COLUMN user_reward_log.used_at IS '보상이 실제로 사용(소진)된 시각입니다. 아직 사용되지 않았다면 NULL입니다.';
COMMENT ON COLUMN user_reward_log.updated_at IS '이 보상 로그 레코드의 정보(주로 상태 또는 사용 시각)가 마지막으로 변경된 시각입니다.';

-- user_reward_log 테이블 인덱스
CREATE INDEX uuidx_user_reward_log_receiver_status ON user_reward_log(receiver_id, reward_status) WHERE receiver_id IS NOT NULL; -- 특정 활성 사용자의 특정 상태 보상 조회
CREATE INDEX uuidx_user_reward_log_expiry ON user_reward_log(reward_expire_at) WHERE reward_status = 'active'::reward_status_enum AND reward_expire_at IS NOT NULL; -- 만료 처리 대상 보상 조회 최적화
CREATE INDEX uuidx_user_reward_log_trigger_event ON user_reward_log(trigger_type, related_event_uuidentifier); -- 특정 이벤트로 발생한 보상 조회
CREATE INDEX uuidx_user_reward_log_source_id ON user_reward_log(source_user_id) WHERE source_user_id IS NOT NULL; -- 특정 추천인이 발생시킨 보상 조회

-- updated_at 컬럼 자동 갱신 트리거
-- (참고: set_updated_at() 함수는 '00_common_functions_and_types.sql' 파일에 최종적으로 통합 정의될 예정)
CREATE TRIGGER trg_set_updated_at_user_reward_log
BEFORE UPDATE ON user_reward_log
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 만료된 보상 상태 자동 업데이트 함수 ('expire_rewards()')는 '00_common_functions_and_types.sql'에 정의될 예정이며,
-- pg_cron 등을 통해 주기적으로 실행되어야 합니다.
-- (참고: expire_rewards() 함수는 reward_status_enum을 정확히 사용하고, 만료된 'active' 상태의 보상을 'expired'로 변경해야 합니다.)