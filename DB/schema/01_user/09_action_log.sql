-- =====================================================================================
-- 파일: 09_user_action_log.sql
-- 모듈: 01_user_module (사용자 모듈)
-- 설명: 사용자의 주요 행동에 대한 메타데이터 및 관리 상태를 기록합니다.
--       실제 상세 행동 로그(특히 metadata)는 Loki를 통해 외부 저장소(S3 또는 OpenSearch)에 저장되는 것을 전제로 합니다.
-- 대상 DB: PostgreSQL Primary RDB (핵심 감사 및 분석 로그 메타데이터)
-- 파티셔닝: 필수 (`created_at` 기준 RANGE 파티셔닝, MVP: 월 또는 주 단위 수동 생성, 스케일업: 일 단위 자동 생성).
-- MVP 중점사항: 핵심 액션 메타데이터, 파티셔닝 기본 설정, 필수 인덱스, 외부 저장소 참조 uuid.
-- 스케일업 고려사항: RLS, 파티션 자동 생성/관리 (pg_partman), Cold Storage로의 데이터 아카이빙, OpenSearch 연동 강화.
-- 개인정보보호: 사용자 탈퇴 시 id는 NULL로 설정되어 로그는 익명으로 보존.
-- =====================================================================================

-- 사용자 행동 로그 테이블
CREATE TABLE user_action_log (
  uuid BIGSERIAL,                                           -- 내부 자동 증가 uuid (PK는 복합키의 일부)
  id id REFERENCES user_info(id) ON DELETE SET NULL, -- 행동을 수행한 사용자 (탈퇴 시 NULL로 설정되어 익명화)
  action TEXT NOT NULL,                                   -- 사용자가 수행한 행동의 종류 (예: 'user_login', 'view_dashboard', 'click_generate_commit_button')
  context TEXT,                                           -- 해당 행동이 발생한 애플리케이션 내 위치나 맥락 (예: 'web_app:/settings/profile', 'vscode_extension:suuidebar')
  
  metadata_summary JSONB,                                 -- 행동 관련 주요 메타데이터 요약 (선택적, 예: {"button_uuid": "save_settings", "page_category": "user_profile"})
  external_metadata_ref_uuid TEXT UNIQUE,                   -- 외부 저장소(Loki/S3 등)에 저장된 상세 metadata의 참조 uuid (Loki/S3의 객체 uuid 또는 고유 경로). NULL일 경우 metadata_summary에 주요 정보 포함 가정.

  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, -- 액션 발생 시각 (파티셔닝 키)

  PRIMARY KEY (uuid, created_at)                            -- 파티션 테이블의 PK는 파티션 키를 포함해야 함
)
PARTITION BY RANGE (created_at);

COMMENT ON TABLE user_action_log IS '사용자의 주요 행동 이력에 대한 메타데이터를 기록하는 로그 테이블입니다. 상세 로그는 Loki를 통해 외부 저장소에 보관될 수 있습니다.';
COMMENT ON COLUMN user_action_log.uuid IS '행동 로그 레코드의 내부 자동 증가 uuid입니다. created_at과 함께 복합 기본 키를 구성합니다.';
COMMENT ON COLUMN user_action_log.id IS '행동을 수행한 사용자의 id입니다. 사용자 탈퇴 시 NULL로 설정되어 로그는 익명으로 보존됩니다.';
COMMENT ON COLUMN user_action_log.action IS '사용자가 수행한 행동을 나타내는 표준화된 문자열입니다 (예: user_login, click_button).';
COMMENT ON COLUMN user_action_log.context IS '행동이 발생한 서비스 내의 위치나 맥락 정보입니다 (예: /dashboard, settings_page).';
COMMENT ON COLUMN user_action_log.metadata_summary IS '외부 저장소에 기록된 상세 메타데이터의 요약본 또는 주요 식별자입니다 (선택적).';
COMMENT ON COLUMN user_action_log.external_metadata_ref_uuid IS 'Loki/S3 등 외부 저장소에 보관된 실제 상세 메타데이터에 대한 고유 참조 uuid입니다 (예: 로그 스트림 uuid 또는 S3 객체 경로).';
COMMENT ON COLUMN user_action_log.created_at IS '행동이 발생한 정확한 시각이며, 테이블 파티셔닝의 기준이 됩니다.';

-- user_action_log 테이블 파티션 생성 예시 (MVP 단계에서는 수동으로 몇 개 생성, 스케일업 시 자동화)
-- 예시: 2025년 5월 파티션 (YYYYMM 형식)
-- CREATE TABLE user_action_log_y2025m05 PARTITION OF user_action_log
-- FOR VALUES FROM ('2025-05-01') TO ('2025-06-01');
-- (참고: 실제 운영 시에는 pg_partman 등을 사용하여 파티션 자동 생성 및 관리가 권장됩니다.)

-- user_action_log 테이블 인덱스
CREATE INDEX uuidx_user_action_log_id_created_at ON user_action_log(id, created_at DESC) WHERE id IS NOT NULL; -- 특정 활성 사용자의 최근 행동 조회
CREATE INDEX uuidx_user_action_log_action_created_at ON user_action_log(action, created_at DESC); -- 특정 행동 유형의 최근 로그 조회
CREATE INDEX uuidx_user_action_log_context_created_at ON user_action_log(context, created_at DESC); -- 특정 컨텍스트의 최근 로그 조회
CREATE INDEX uuidx_user_action_log_external_ref_uuid ON user_action_log(external_metadata_ref_uuid) WHERE external_metadata_ref_uuid IS NOT NULL; -- 외부 참조 uuid로 검색
-- created_at은 PK의 일부이므로 개별 인덱스 불필요.