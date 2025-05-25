-- =====================================================================================
-- 파일: 02_repo_connections.sql
-- 모듈: 04_repo_module / 01_repositories (저장소 기본 정보)
-- 설명: Comfort Commit 서비스와 등록된 저장소 간의 연동 상태, 서비스별 설정,
--       및 마지막 연결/작업 환경 정보를 관리합니다.
-- 대상 DB: PostgreSQL Primary RDB (저장소 연동 상태 및 설정 데이터)
-- 파티셔닝: 없음
-- MVP 중점사항: 저장소별 연결 상태, 마지막 성공/시도 시각, 에러 상세, Webhook ID,
--             토큰 참조 ID, 서비스 설정 JSONB, 표준 created_at/updated_at.
-- 스케일업 고려사항: RLS 적용, 연결 히스토리 로그 분리, 설정 JSONB 필드 세분화,
--                  주기적인 연결 상태 자동 점검 및 알림.
-- =====================================================================================

-- ENUM 타입 정의 (필요시 04_repo_module/00_repo_enums_and_types.sql 파일로 통합 예정)
CREATE TYPE repo_connection_status_enum AS ENUM ('pending_verification', 'connected', 'disconnected_by_user', 'error_authentication', 'error_permissions', 'error_not_found', 'syncing', 'temporarily_unavailable');
COMMENT ON TYPE repo_connection_status_enum IS '저장소와 Comfort Commit 서비스 간의 연동 상태입니다.';

CREATE TYPE repo_connection_method_enum AS ENUM ('oauth_app', 'personal_access_token', 'ssh_key_reference', 'github_codespaces', 'other');
COMMENT ON TYPE repo_connection_method_enum IS '저장소에 접근하기 위해 우선적으로 사용되는 연결 방식입니다.';

-- 테이블명: repo_connections
CREATE TABLE repo_connections (
    repo_uuid UUID PRIMARY KEY REFERENCES repo_master(repo_uuid) ON DELETE CASCADE, -- repo_master 테이블의 저장소 UUID (PK, FK)
    
    connection_status repo_connection_status_enum DEFAULT 'pending_verification', -- 현재 연결 상태
    last_successful_connection_at TIMESTAMP,      -- 마지막으로 성공적인 연결(예: API 호출, Webhook 수신)이 있었던 시각
    last_connection_attempt_at TIMESTAMP,         -- 마지막 연결 시도 시각 (성공/실패 무관)
    connection_error_details TEXT,                -- 연결 실패 시 상세 오류 메시지 또는 코드
    
    webhook_id_on_platform TEXT,                  -- VCS 플랫폼에 등록된 Webhook의 ID (Webhook을 사용하는 경우)
    access_token_ref_id TEXT,                     -- 이 저장소 접근에 사용되는 Access Token의 외부 저장소 참조 ID 또는 Comfort Commit 내부 토큰 관리 시스템의 식별자. 실제 토큰 값은 저장하지 않음.
    preferred_connection_method repo_connection_method_enum, -- 사용자가 선호하거나 시스템이 주로 사용하는 연결 방식
    last_accessed_from_os TEXT,                   -- 마지막으로 이 저장소 관련 작업을 수행한 사용자 환경의 OS 정보 (선택적)

    comfort_commit_config_json JSONB DEFAULT '{}'::JSONB, -- 해당 저장소에 대한 Comfort Commit 서비스의 특화 설정 
                                                          -- 예: {"auto_analysis_enabled": true, "default_llm_model_for_repo": "gpt-4o", "commit_style_template_id": "uuid", "analysis_branch_filter": ["main", "develop"]}
    
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, -- 이 연결 설정 레코드가 생성된 시각
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP  -- 이 연결 설정 레코드가 마지막으로 수정된 시각 (트리거로 자동 관리)
);

COMMENT ON TABLE repo_connections IS 'Comfort Commit 서비스와 등록된 저장소 간의 연동 상태, 서비스별 설정, 마지막 연결 정보 등을 관리합니다.';
COMMENT ON COLUMN repo_connections.repo_uuid IS 'repo_master 테이블의 저장소 UUID를 참조하며, 이 테이블의 기본 키입니다.';
COMMENT ON COLUMN repo_connections.connection_status IS '현재 저장소와의 연동 상태를 나타냅니다 (예: connected, error_authentication).';
COMMENT ON COLUMN repo_connections.last_successful_connection_at IS '서비스가 저장소와 마지막으로 성공적인 상호작용(API 호출, Webhook 이벤트 수신 등)을 한 시각입니다.';
COMMENT ON COLUMN repo_connections.webhook_id_on_platform IS 'VCS 플랫폼(GitHub, GitLab 등)에 등록된 Webhook의 고유 ID입니다. Webhook 기반 이벤트 수신 시 사용됩니다.';
COMMENT ON COLUMN repo_connections.access_token_ref_id IS '저장소 접근에 필요한 인증 토큰의 외부 보안 저장소 참조 ID 또는 내부 토큰 관리 시스템의 식별자입니다. 실제 토큰은 여기에 저장되지 않습니다.';
COMMENT ON COLUMN repo_connections.preferred_connection_method IS '이 저장소에 접근하거나 사용자가 주로 사용하는 연결 방식입니다 (예: OAuth 앱, PAT).';
COMMENT ON COLUMN repo_connections.last_accessed_from_os IS '사용자가 마지막으로 이 저장소 관련 작업을 수행했을 때의 클라이언트 OS 정보입니다 (예: Windows, macOS, Linux).';
COMMENT ON COLUMN repo_connections.comfort_commit_config_json IS '이 특정 저장소에만 적용되는 Comfort Commit 서비스의 설정값을 JSONB 형태로 저장합니다 (예: 자동 분석 활성화 여부, 기본 LLM 모델 등).';
COMMENT ON COLUMN repo_connections.updated_at IS '이 연결 설정 정보가 마지막으로 수정된 시각입니다.';

-- 인덱스
CREATE INDEX idx_repo_connections_status ON repo_connections(connection_status); -- 특정 연결 상태의 저장소 조회
CREATE INDEX idx_repo_connections_access_token_ref ON repo_connections(access_token_ref_id) WHERE access_token_ref_id IS NOT NULL;
CREATE INDEX idx_repo_connections_webhook_id ON repo_connections(webhook_id_on_platform) WHERE webhook_id_on_platform IS NOT NULL;

-- updated_at 컬럼 자동 갱신 트리거
-- (set_updated_at() 함수는 '00_common_functions_and_types.sql' 파일에 정의될 예정)
CREATE TRIGGER trg_set_updated_at_repo_connections
BEFORE UPDATE ON repo_connections
FOR EACH ROW EXECUTE FUNCTION set_updated_at();