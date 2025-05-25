-- =====================================================================================
-- 파일: 10_user_deletion_request.sql
-- 모듈: 01_user_module (사용자 모듈)
-- 설명: 사용자의 계정 탈퇴 요청 및 처리 상태를 기록합니다.
-- 대상 DB: PostgreSQL Primary RDB (사용자 관리 데이터)
-- 파티셔닝: 없음 (일반적으로 데이터 양이 많지 않음)
-- MVP 중점사항: 탈퇴 요청 기록, 처리 상태 관리, ENUM 타입 사용, 필수 인덱스.
-- 스케일업 고려사항: RLS 적용, 탈퇴 처리 자동화 연동, GDPR 등 규정 준수를 위한 상세 로그 강화.
-- 개인정보보호: 사용자 계정 삭제 후에도 이 "요청 기록"은 user_uuid가 NULL로 설정되어 익명으로 보존.
-- =====================================================================================

-- 사용자 계정 탈퇴 요청 상태 ENUM 타입 정의
-- (향후 00_common_functions_and_types.sql 파일로 통합 예정)
CREATE TYPE deletion_request_status_enum AS ENUM (
    'pending_confirmation',   -- 사용자의 이메일 등 추가 확인 대기
    'pending_processing',     -- 관리자 또는 시스템의 처리 대기
    'processing_in_progress', -- 데이터 삭제/익명화 작업 진행 중
    'completed_deletion',     -- 사용자 데이터 완전 삭제 완료
    'completed_anonymization',-- 사용자 데이터 익명화 완료 (로그 등 일부 보존 시)
    'rejected_by_admin',      -- 관리자에 의해 요청 거부
    'cancelled_by_user',      -- 사용자에 의해 요청 철회
    'error_during_processing' -- 처리 중 오류 발생
);
COMMENT ON TYPE deletion_request_status_enum IS '사용자 계정 탈퇴 요청의 처리 상태를 나타내는 값들의 집합입니다.';

-- 사용자 계정 탈퇴 요청 테이블
CREATE TABLE user_deletion_request (
  request_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),    -- 각 탈퇴 요청별 고유 ID (한 사용자가 여러 번 요청/재요청 가능)
  user_uuid UUID NOT NULL REFERENCES user_info(uuid) ON DELETE SET NULL, -- 탈퇴를 요청한 사용자 (user_info에서 삭제되어도 이 요청 기록은 user_uuid가 NULL로 설정되어 보존)

  reason_category TEXT,                                     -- 탈퇴 사유 카테고리 (선택적. 예: 'service_dissatisfaction', 'privacy_concern'). (스케일업 시: ENUM 또는 별도 lookup 테이블 참조 고려)
  reason_detail TEXT,                                       -- 사용자가 직접 입력한 상세 탈퇴 사유
  additional_feedback TEXT,                                 -- 탈퇴 관련 추가 피드백

  status deletion_request_status_enum NOT NULL DEFAULT 'pending_confirmation', -- 탈퇴 요청 처리 상태 (ENUM 타입 적용)
  requested_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, -- 사용자가 탈퇴를 요청한 시각
  confirmed_by_user_at TIMESTAMP,                         -- 사용자가 이메일 등으로 탈퇴 의사를 최종 확인한 시각 (2단계 확인 시)
  
  processing_started_at TIMESTAMP,                        -- 실제 데이터 처리(삭제/익명화) 작업 시작 시각
  completed_at TIMESTAMP,                                 -- 실제 데이터 처리(삭제 또는 익명화) 완료 시각
  processed_by TEXT,                                      -- 처리 담당자 또는 시스템 (예: 'admin_user_X', 'automated_deletion_job_v1.2')
  processing_log JSONB,                                   -- 처리 과정에서의 주요 단계별 로그나 발생한 이슈 기록 (선택적)
                                                          -- 예: 
                                                          -- {
                                                          --   "stages": [
                                                          --     {"name": "backup_user_data", "status": "success", "timestamp": "..."},
                                                          --     {"name": "anonymize_activity_logs", "status": "in_progress", "timestamp": "..."}
                                                          --   ],
                                                          --   "final_outcome_note": "Anonymization completed. Some aggregated stats retained.",
                                                          --   "error_details": null
                                                          -- }
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP  -- 이 탈퇴 요청 레코드 정보가 마지막으로 수정된 시각
);

COMMENT ON TABLE user_deletion_request IS '사용자의 계정 탈퇴 요청 및 그 처리 과정을 기록합니다. 사용자 계정이 삭제된 후에도 이 요청 기록은 익명화되어 보존될 수 있습니다.';
COMMENT ON COLUMN user_deletion_request.request_id IS '각 탈퇴 요청 건을 고유하게 식별하는 UUID입니다.';
COMMENT ON COLUMN user_deletion_request.user_uuid IS '탈퇴를 요청한 사용자의 UUID (user_info.uuid 참조)입니다. 사용자 계정이 삭제되면 NULL로 설정됩니다.';
COMMENT ON COLUMN user_deletion_request.reason_category IS '사용자가 선택한 탈퇴 사유의 분류입니다. 상세 내용은 reason_detail에 기록됩니다.';
COMMENT ON COLUMN user_deletion_request.status IS '탈퇴 요청의 현재 처리 단계를 나타냅니다.';
COMMENT ON COLUMN user_deletion_request.requested_at IS '사용자가 처음 탈퇴 요청을 제출한 시각입니다.';
COMMENT ON COLUMN user_deletion_request.completed_at IS '탈퇴 요청에 따른 모든 데이터 처리(삭제 또는 익명화)가 완료된 시각입니다.';
COMMENT ON COLUMN user_deletion_request.processing_log IS '탈퇴 처리 과정에서의 세부 로그나 발생한 문제를 JSONB 형태로 기록합니다. 예: {"stages": [{"name": "anonymize_logs", "status": "success"}]}';
COMMENT ON COLUMN user_deletion_request.updated_at IS '이 탈퇴 요청 레코드의 정보(주로 상태)가 마지막으로 변경된 시각입니다.';

-- user_deletion_request 테이블 인덱스
CREATE INDEX idx_user_deletion_request_user_uuid ON user_deletion_request(user_uuid) WHERE user_uuid IS NOT NULL; -- 특정 사용자의 탈퇴 요청 조회
CREATE INDEX idx_user_deletion_request_status ON user_deletion_request(status); -- 특정 상태의 탈퇴 요청 목록 조회 (예: 처리 대기 중인 요청)
CREATE INDEX idx_user_deletion_request_requested_at ON user_deletion_request(requested_at DESC); -- 최근 요청 순으로 정렬

-- updated_at 컬럼 자동 갱신 트리거
-- (참고: set_updated_at() 함수는 '00_common_functions_and_types.sql' 파일에 최종적으로 통합 정의될 예정)
CREATE TRIGGER trg_set_updated_at_user_deletion_request
BEFORE UPDATE ON user_deletion_request
FOR EACH ROW EXECUTE FUNCTION set_updated_at();