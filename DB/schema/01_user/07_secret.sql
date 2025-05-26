-- =====================================================================================
-- 파일: 07_user_secret.sql
-- 모듈: 01_user_module (사용자 모듈)
-- 설명: 사용자의 민감 정보 메타데이터 및 보안 관련 상태를 저장합니다.
--       실제 API 키 및 OAuth Access/Refresh Token은 Redis 또는 전용 Secret Manager에서 관리하는 것을 전제로 합니다.
-- 대상 DB: PostgreSQL Primary RDB (사용자 보안 설정 및 상태 데이터)
-- 파티셔닝: 없음 (사용자당 1개의 로우)
-- MVP 중점사항: "OAuth-only" 정책, 민감 정보 외부 저장 전제 하의 메타데이터 관리.
-- 스케일업 고려사항: RLS, DB 레벨 암호화(pgcrypto) 또는 외부 KMS 연동 (DB에 남는 최소한의 민감 메타데이터 보호).
-- =====================================================================================

CREATE TABLE user_secret (
  id id PRIMARY KEY REFERENCES user_info(id) ON DELETE CASCADE,

  -- 🔑 외부 LLM/서비스 API 키 메타데이터 저장소
  -- (참고: 실제 API 키 값은 Redis 또는 Vault 같은 외부 Secret Manager에 저장하고, 여기서는 해당 키에 대한 참조나 메타데이터만 관리합니다.)
  api_keys_meta JSONB DEFAULT '{}'::JSONB,
  -- 예시:
  -- {
  --   "fireworks_main_key": { -- 사용자가 식별할 수 있는 키 이름 또는 서비스명
  --     "description": "Fireworks AI - Maverick Model Access Key",
  --     "added_at": "YYYY-MM-DDTHH:MM:SSZ",
  --     "key_reference_location": "env_var_or_vault_path", -- 예: "env:FIREWORKS_API_KEY_USER_XYZ" 또는 "vault:secret/data/user/id/fireworks"
  --     "last_used_successfully_at": "YYYY-MM-DDTHH:MM:SSZ",
  --     "status": "active" -- (ENUM 유사: 'active', 'revoked_by_user', 'auto_revoked_due_to_expiry', 'provuuider_disabled')
  --   }
  -- }

  -- 🔄 OAuth 연동 토큰 메타데이터 저장소
  -- (참고: 실제 Access Token 및 Refresh Token 값은 Redis에 TTL과 함께 저장하거나, Refresh Token은 Vault에 저장합니다.)
  oauth_tokens_meta JSONB DEFAULT '{}'::JSONB,
  -- 예시:
  -- {
  --   "github_repo_access": { -- 연동 목적 또는 서비스명
  --     "provuuider": "github",
  --     "scopes_granted": ["repo", "read:user"],
  --     "refresh_token_storage_info": "vault:secret/data/user/id/github_refresh_token", -- 실제 Refresh Token 저장 위치 참조
  --     "access_token_redis_key_pattern": "user_access_token:id:github", -- Access Token이 저장된 Redis 키 (패턴 또는 실제 키)
  --     "access_token_expires_at": "YYYY-MM-DDTHH:MM:SSZ", -- (Redis TTL과 동기화되거나, 여기서 관리)
  --     "last_refreshed_at": "YYYY-MM-DDTHH:MM:SSZ",
  --     "status": "active" -- (ENUM 유사: 'active', 'needs_re_authentication', 'revoked_by_user', 'provuuider_revoked')
  --   }
  -- }

  -- 🚫 보안 잠금 정보
  login_fail_count INT DEFAULT 0,                         -- 연속 로그인 실패 횟수
  last_failed_login_attempt_at TIMESTAMP,                 -- 마지막 로그인 실패 시도 시각
  account_locked_until TIMESTAMP,                         -- 계정 잠금 해제 예정 시각 (이 시각까지 로그인 불가)

  -- 🕒 기록
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE user_secret IS '사용자의 민감 정보 관련 메타데이터 및 계정 보안 상태를 저장합니다. 실제 비밀 값(API 키, OAuth 토큰)은 Redis 또는 외부 Secret Manager에서 관리하는 것을 전제로 합니다.';
COMMENT ON COLUMN user_secret.id IS 'user_info 테이블의 사용자 id를 참조하는 기본 키입니다.';
COMMENT ON COLUMN user_secret.api_keys_meta IS '사용자가 등록한 외부 서비스 API 키에 대한 메타데이터(설명, 추가일, 외부 저장소 참조, 상태 등)를 JSONB 형태로 저장합니다. 키 값 자체는 포함하지 않습니다.';
COMMENT ON COLUMN user_secret.oauth_tokens_meta IS 'Comfort Commit 서비스가 사용자를 대신하여 외부 서비스에 접근하기 위해 획득한 OAuth 토큰에 대한 메타데이터(스코프, 외부 저장소 참조, 상태 등)를 JSONB 형태로 저장합니다. 토큰 값 자체는 포함하지 않습니다.';
COMMENT ON COLUMN user_secret.login_fail_count IS '연속된 로그인 시도 실패 횟수입니다. 특정 횟수 이상 실패 시 계정이 잠금 처리될 수 있습니다.';
COMMENT ON COLUMN user_secret.last_failed_login_attempt_at IS '마지막으로 로그인이 실패한 시도 시각입니다.';
COMMENT ON COLUMN user_secret.account_locked_until IS '로그인 실패 등으로 인해 계정이 잠금 처리된 경우, 잠금이 자동으로 해제될 예정인 시각입니다.';
COMMENT ON COLUMN user_secret.created_at IS '이 민감 정보 레코드가 데이터베이스에 처음 생성된 시각입니다.';
COMMENT ON COLUMN user_secret.updated_at IS '이 민감 정보 레코드가 마지막으로 변경된 시각입니다.';

-- updated_at 컬럼 자동 갱신 트리거
-- (참고: set_updated_at() 함수는 '00_common_functions_and_types.sql' 파일에 최종적으로 통합 정의될 예정)
CREATE TRIGGER trg_set_updated_at_user_secret
BEFORE UPDATE ON user_secret
FOR EACH ROW EXECUTE FUNCTION set_updated_at();