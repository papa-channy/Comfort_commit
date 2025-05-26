-- =====================================================================================
-- 파일: 08_user_feedback_log.sql
-- 모듈: 01_user_module (사용자 모듈)
-- 설명: 사용자가 제출한 피드백의 메타데이터 및 관리 상태를 기록합니다.
--       피드백 원문(content)은 Loki를 통해 외부 저장소(S3 또는 OpenSearch)에 저장되는 것을 전제로 합니다.
-- 대상 DB: PostgreSQL Primary RDB (서비스 운영 및 개선 데이터)
-- 파티셔닝: 고려 가능 (created_at 기준, 데이터가 매우 많아질 경우 - 스케일업 시)
-- MVP 중점사항: 핵심 피드백 메타데이터, 관리용 상태 컬럼, 외부 저장소 참조 uuid.
-- 스케일업 고려사항: RLS 적용, feedback_type ENUM화, 파티셔닝, OpenSearch 연동 강화 (원문 검색).
-- =====================================================================================

-- 사용자 피드백 로그 테이블
CREATE TABLE user_feedback_log (
  uuid SERIAL PRIMARY KEY,                                  -- 내부 자동 증가 uuid
  id id REFERENCES user_info(id) ON DELETE SET NULL, -- 피드백 남긴 사용자 (탈퇴 시 피드백은 익명으로 보존)

  feedback_type TEXT,                                     -- 피드백 유형 (예: 'bug_report', 'feature_request', 'general_comment'). (스케일업 시: ENUM 타입으로 변경 고려)
  content_summary TEXT,                                   -- 피드백 내용 요약 (예: 첫 200자, 전문은 외부 저장). 원문이 짧으면 전문 저장 가능.
  external_content_ref_uuid TEXT UNIQUE,                    -- 외부 저장소(Loki/S3 등)에 저장된 피드백 원문의 참조 uuid (Loki/S3의 객체 uuid 또는 고유 경로). NULL일 경우 content_summary에 전문 포함 가정.
  page_context TEXT,                                      -- 피드백이 제출된 페이지 URL 또는 애플리케이션 내 화면 식별자
  score INT CHECK (score IS NULL OR (score >= 1 AND score <= 10)), -- 만족도 점수 (1~10점 스케일, 선택적)

  contact_email TEXT,                                     -- 사용자가 추가 연락을 위해 남긴 이메일 (user_info.email과 다를 수 있음, 선택적)
  is_resolved BOOLEAN DEFAULT FALSE,                      -- 해당 피드백 처리 완료 여부 (관리용)
  resolved_at TIMESTAMP,                                  -- 피드백 처리 완료 시각
  resolver_note TEXT,                                     -- 피드백 처리 내용에 대한 관리자 또는 담당자 메모

  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, -- 피드백 제출 시각
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP -- 이 피드백 로그 레코드가 마지막으로 수정된 시각 (주로 관리 상태 변경 시)
);

COMMENT ON TABLE user_feedback_log IS '사용자가 서비스에 대해 제출한 피드백의 메타데이터 및 관리 상태를 기록합니다. 장문의 피드백 원문은 Loki를 통해 외부 저장소(S3 등)에 저장될 수 있습니다.';
COMMENT ON COLUMN user_feedback_log.uuid IS '피드백 로그 레코드의 내부 자동 증가 uuid입니다.';
COMMENT ON COLUMN user_feedback_log.id IS '피드백을 제출한 사용자의 id입니다. 사용자 탈퇴 시 NULL로 설정되어 피드백은 익명으로 보존됩니다.';
COMMENT ON COLUMN user_feedback_log.feedback_type IS '제출된 피드백의 유형입니다 (예: 버그 신고, 기능 제안). 스케일업 시 ENUM 타입 사용을 고려합니다.';
COMMENT ON COLUMN user_feedback_log.content_summary IS '피드백 원문 내용의 요약본 또는 전문(짧은 경우)입니다. 원문이 길 경우 external_content_ref_uuid를 통해 외부에서 조회합니다.';
COMMENT ON COLUMN user_feedback_log.external_content_ref_uuid IS 'Loki/S3 등 외부 저장소에 보관된 실제 피드백 원문 데이터에 대한 고유 참조 uuid입니다 (예: 객체 스토리지의 경로 또는 로그 시스템의 uuid).';
COMMENT ON COLUMN user_feedback_log.page_context IS '피드백이 제출된 서비스 내 페이지의 URL 또는 화면 식별자입니다.';
COMMENT ON COLUMN user_feedback_log.score IS '피드백과 함께 제출된 사용자의 만족도 점수입니다 (1~10점 척도, 선택 사항).';
COMMENT ON COLUMN user_feedback_log.contact_email IS '사용자가 피드백에 대해 추가적인 연락을 받기 위해 선택적으로 남긴 이메일 주소입니다.';
COMMENT ON COLUMN user_feedback_log.is_resolved IS '관리자가 해당 피드백을 검토하고 처리(또는 종결)했는지 여부를 나타냅니다.';
COMMENT ON COLUMN user_feedback_log.resolved_at IS '피드백이 처리 완료된 시각입니다.';
COMMENT ON COLUMN user_feedback_log.resolver_note IS '피드백 처리 결과 또는 과정에 대한 관리자 또는 담당자의 내부 메모입니다.';
COMMENT ON COLUMN user_feedback_log.created_at IS '사용자가 피드백을 제출한 시각입니다.';
COMMENT ON COLUMN user_feedback_log.updated_at IS '이 피드백 로그 레코드가 마지막으로 수정된 시각입니다 (예: 처리 상태 변경 시).';

-- user_feedback_log 테이블 인덱스
CREATE INDEX uuidx_user_feedback_log_id ON user_feedback_log(id) WHERE id IS NOT NULL; -- 특정 사용자가 남긴 피드백 조회
CREATE INDEX uuidx_user_feedback_log_feedback_type ON user_feedback_log(feedback_type); -- 피드백 유형별 조회
CREATE INDEX uuidx_user_feedback_log_created_at ON user_feedback_log(created_at DESC); -- 최근 피드백 순 조회
CREATE INDEX uuidx_user_feedback_log_is_resolved_created_at ON user_feedback_log(is_resolved, created_at DESC); -- 미처리/처리 피드백 최근 순 조회
CREATE INDEX uuidx_user_feedback_log_external_ref_uuid ON user_feedback_log(external_content_ref_uuid) WHERE external_content_ref_uuid IS NOT NULL; -- 외부 참조 uuid로 검색

-- updated_at 컬럼 자동 갱신 트리거
-- (set_updated_at() 함수는 '00_common_functions_and_types.sql' 파일에 정의될 예정)
CREATE TRIGGER trg_set_updated_at_user_feedback_log
BEFORE UPDATE ON user_feedback_log
FOR EACH ROW EXECUTE FUNCTION set_updated_at();