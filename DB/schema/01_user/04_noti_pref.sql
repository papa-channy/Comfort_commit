-- =====================================================================================
-- 파일: 04_user_notification_pref.sql
-- 모듈: 01_user_module (사용자 모듈)
-- 설명: 사용자의 알림 수신 설정을 관리합니다.
-- 대상 DB: PostgreSQL Primary RDB (사용자 설정 데이터)
-- 파티셔닝: 없음
-- MVP 중점사항: 다양한 알림 채널 활성화 여부, JSONB를 사용한 유연한 알림 규칙 설정.
-- 스케일업 고려사항: RLS 적용, 알림 규칙의 복잡도 증가 시 JSONB 인덱싱 최적화.
-- =====================================================================================

-- 사용자 알림 설정 테이블
CREATE TABLE user_notification_pref (
  -- 🆔 식별자
  uuid SERIAL PRIMARY KEY,                                  -- 내부 자동 증가 uuid
  id id NOT NULL REFERENCES user_info(id) ON DELETE CASCADE, -- 사용자 식별자 (user_info.id 참조)

  -- 📌 알림 범위 및 유형 설정
  alert_configurations JSONB DEFAULT '{}'::JSONB,
  -- 예시:
  -- {
  --   "commit_generation": {"types": ["success", "failure"], "channels": ["email", "slack"]},
  --   "system_maintenance": {"types": ["scheduled_downtime"], "channels": ["email"]},
  --   "new_feature_release": {"types": ["announcement"], "channels": ["app_push", "email"]}
  -- }
  -- 키는 '알림 이벤트 카테고리', 값은 해당 카테고리 내 '알림 타입' 배열과 '수신 채널' 배열을 포함하는 객체.

  -- 📢 알림 채널 활성화 여부 (실제 주소/토큰은 user_secret 테이블에서 관리)
  enable_email_noti BOOLEAN DEFAULT TRUE,                 -- 이메일 알림 활성화 여부 (기본 활성화, user_info.email 사용)
  enable_slack_noti BOOLEAN DEFAULT FALSE,                -- Slack 알림 활성화 여부
  enable_kakao_noti BOOLEAN DEFAULT FALSE,                -- Kakao 알림 활성화 여부
  enable_discord_noti BOOLEAN DEFAULT FALSE,              -- Discord 알림 활성화 여부
  enable_telegram_noti BOOLEAN DEFAULT FALSE,             -- Telegram 알림 활성화 여부
  enable_app_push_noti BOOLEAN DEFAULT FALSE,             -- 모바일 앱 푸시 알림 활성화 여부

  -- 🔄 자동 트리거 (Comfort Commit 기능 자동 시작/알림 발송 시점 조건)
  task_trigger_preferences JSONB DEFAULT '{}'::JSONB,
  -- 예시:
  -- {
  --   "on_uuide_close": {"action": "trigger_commit_suggestion", "delay_minutes": 1},
  --   "on_git_push_manual": {"action": "log_activity_only"}
  -- }
  -- 키는 '발생 이벤트', 값은 해당 이벤트 발생 시 '수행할 액션'과 관련 '옵션'을 포함하는 객체.

  -- 🔕 조용한 시간 설정 (해당 시간대엔 알림 비활성화)
  quiet_hours_start TIME,                                 -- 알림 차단 시작 시각 (예: '22:00:00')
  quiet_hours_end TIME,                                   -- 알림 차단 종료 시각 (예: '08:00:00')
  quiet_hours_timezone TEXT DEFAULT 'Asia/Seoul',         -- 조용한 시간 적용 기준 시간대 (user_info.timezone과 다를 수 있음)

  -- 🚫 전체 알림 차단 여부
  is_all_notifications_enabled BOOLEAN DEFAULT TRUE,      -- 모든 알림 허용 여부 (False면 위 설정과 무관하게 모든 알림 비활성화)

  -- 🕒 기록
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, -- 이 설정 레코드가 처음 생성된 시각
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP -- 이 설정이 마지막으로 수정된 시각 (trg_set_updated_at_user_notification_pref 트리거로 자동 관리)
);

COMMENT ON TABLE user_notification_pref IS '사용자별 알림 수신 채널, 알림 유형, 조용한 시간 등 개인화된 알림 설정을 저장합니다.';
COMMENT ON COLUMN user_notification_pref.uuid IS '알림 설정 레코드의 내부 자동 증가 uuid입니다.';
COMMENT ON COLUMN user_notification_pref.id IS 'user_info 테이블의 사용자 id를 참조합니다.';
COMMENT ON COLUMN user_notification_pref.alert_configurations IS '사용자가 어떤 상황/범위에서 어떤 종류의 알림을 어떤 채널로 받을지 정의하는 JSONB 객체입니다. 예: {"commit_generation": {"types": ["success"], "channels": ["email"]}}';
COMMENT ON COLUMN user_notification_pref.enable_email_noti IS '이메일 채널을 통한 알림 수신 여부입니다. 실제 이메일 주소는 user_info.email을 사용하며, 발송 관련 설정은 user_secret 또는 시스템 설정을 따릅니다.';
COMMENT ON COLUMN user_notification_pref.enable_slack_noti IS 'Slack 채널을 통한 알림 수신 여부입니다.';
COMMENT ON COLUMN user_notification_pref.enable_kakao_noti IS '카카오톡 채널을 통한 알림 수신 여부입니다.';
COMMENT ON COLUMN user_notification_pref.enable_discord_noti IS 'Discord 채널을 통한 알림 수신 여부입니다.';
COMMENT ON COLUMN user_notification_pref.enable_telegram_noti IS 'Telegram 채널을 통한 알림 수신 여부입니다.';
COMMENT ON COLUMN user_notification_pref.enable_app_push_noti IS '모바일 애플리케이션 푸시 알림 수신 여부입니다.';
COMMENT ON COLUMN user_notification_pref.task_trigger_preferences IS 'Comfort Commit의 특정 기능이 자동으로 시작되거나 알림이 발송되는 조건을 정의하는 JSONB 객체입니다. 예: {"on_uuide_close": {"action": "trigger_commit_suggestion"}}';
COMMENT ON COLUMN user_notification_pref.quiet_hours_start IS '알림 수신을 원치 않는 시간대의 시작 시각입니다.';
COMMENT ON COLUMN user_notification_pref.quiet_hours_end IS '알림 수신을 원치 않는 시간대의 종료 시각입니다.';
COMMENT ON COLUMN user_notification_pref.quiet_hours_timezone IS '조용한 시간(Quiet Hours)을 적용할 기준 시간대입니다. 사용자의 기본 시간대(user_info.timezone)와 다를 수 있습니다.';
COMMENT ON COLUMN user_notification_pref.is_all_notifications_enabled IS '모든 알림 채널 및 유형에 대한 마스터 활성화/비활성화 스위치입니다.';
COMMENT ON COLUMN user_notification_pref.created_at IS '이 알림 설정 레코드가 데이터베이스에 처음 생성된 시각입니다.';
COMMENT ON COLUMN user_notification_pref.updated_at IS '이 알림 설정이 마지막으로 변경된 시각입니다.';

-- user_notification_pref 테이블 인덱스
CREATE INDEX uuidx_user_notification_pref_id ON user_notification_pref(id); -- 특정 사용자의 알림 설정 조회
CREATE INDEX uuidx_user_notification_pref_alert_config_gin ON user_notification_pref USING GIN(alert_configurations); -- JSONB 내부 검색 최적화 (예: 특정 알림 타입을 설정한 사용자 검색)
CREATE INDEX uuidx_user_notification_pref_task_trigger_gin ON user_notification_pref USING GIN(task_trigger_preferences); -- JSONB 내부 검색 최적화
-- (참고: 각 enable_<channel>_noti 컬럼은 BOOLEAN이라 개별 인덱스 효율 낮음. 필요시 복합 인덱스 고려)

-- updated_at 컬럼 자동 갱신 트리거
-- (참고: set_updated_at() 함수는 '00_common_functions_and_types.sql' 파일에 최종적으로 통합 정의될 예정)
CREATE TRIGGER trg_set_updated_at_user_notification_pref
BEFORE UPDATE ON user_notification_pref
FOR EACH ROW EXECUTE FUNCTION set_updated_at();