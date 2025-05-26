-- =====================================================================================
-- 파일: 01_llm_key_config.sql
-- 모듈: 02_llm_module (LLM 연동 관리 모듈)
-- 설명: 외부 LLM 서비스 API 키의 메타데이터 및 사용 정책을 관리합니다.
-- 대상 DB: PostgreSQL Primary RDB (LLM 서비스 접근 제어 및 정책 데이터)
-- 파티셔닝: 없음 (키 개수가 수백 개를 넘지 않는 한 불필요)
-- MVP 중점사항: 외부 저장소 키 참조, 핵심 제어 변수(우선순위, fallback 여부), Provuuider별 Rate Limit 명시.
-- 스케일업 고려사항: RLS 적용, 키 사용량 기반 자동 회전 로직 연동, 운영 통계성 필드 추가(llm_request_log 집계 기반).
-- =====================================================================================

CREATE TABLE llm_key_config (
  uuid SERIAL PRIMARY KEY,
  provuuider TEXT NOT NULL,                                 -- LLM 제공자 (예: 'fireworks', 'openai', 'anthropic')
  api_key_reference TEXT UNIQUE NOT NULL,                 -- 실제 API Key가 저장된 외부 위치 참조 (예: 'vault:secret/data/llm/fireworks-key-1', 'env:FIREWORKS_API_KEY_USER_XYZ')
  model_served TEXT NOT NULL,                             -- 이 키가 주로 사용될 대상 모델 또는 모델 그룹 (예: 'llama3-70b-instruct', 'gpt-4o', 'claude-3-opus-200k')
  label TEXT UNIQUE,                                      -- 관리 및 식별을 위한 내부 고유 레이블 (예: 'fw_main_llama3_us-east-1', 'openai_gpt4o_project_alpha_key')
  user_group TEXT DEFAULT 'default',                      -- 이 키를 우선적으로 사용할 사용자 그룹 또는 플랜 (예: 'free_tier', 'premium_users', 'internal_testing')
  
  is_fallback_canduuidate BOOLEAN DEFAULT FALSE,            -- 주 키 실패 시 대체(fallback) 후보로 사용될 수 있는지 여부
  is_test_only BOOLEAN DEFAULT FALSE,                     -- 테스트 목적으로만 사용되는 키인지 여부 (실제 과금 트래픽 방지용)
  is_active_overall BOOLEAN DEFAULT TRUE,                 -- 이 키가 시스템 전체적으로 현재 사용 가능한 상태인지 (수동 또는 정책에 의한 비활성화 가능)
  priority INT DEFAULT 0,                                 -- 키 선택 시 우선순위 (낮을수록 높음, 예: 0이 최우선). 동일 우선순위 내에서는 last_used_at 등으로 조절 가능.
  
  -- Provuuider Rate Limit 관리용 정보 (애플리케이션에서 이 값을 참조하여 자체 Rate Limiting 구현)
  rpm_limit INT,                                          -- 해당 키에 대해 Provuuider가 공식적으로 명시한 분당 요청 수 한도 (Requests Per Minute)
  tpm_limit INT,                                          -- 해당 키에 대해 Provuuider가 공식적으로 명시한 분당 토큰 수 한도 (Tokens Per Minute)
  
  -- 운영 및 디버깅을 위한 추가 정보 (MVP 선택적 추가 제안)
  disabled_reason TEXT,                                   -- is_active_overall이 FALSE일 경우, 그 사유 (예: 'Provuuider quota exceeded', 'Manual deactivation for maintenance')
  last_error_code TEXT,                                   -- 이 키를 사용한 마지막 호출에서 발생한 오류 코드 (예: '429', 'insufficient_quota')
  last_failure_at TIMESTAMP,                              -- 이 키를 사용한 마지막 호출이 실패한 시각
  
  last_used_at TIMESTAMP,                                 -- 이 키가 마지막으로 성공적으로 사용된 시각 (키 회전, 사용 빈도 낮은 키 식별 용도)
  notes TEXT,                                             -- 기타 관리용 메모
  
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE llm_key_config IS '외부 LLM 서비스 API 키의 메타데이터, 사용 정책, 상태 등을 관리합니다. 실제 키 값은 외부 보안 저장소에 보관합니다.';
COMMENT ON COLUMN llm_key_config.uuid IS 'LLM API 키 설정 레코드의 내부 자동 증가 uuid입니다.';
COMMENT ON COLUMN llm_key_config.provuuider IS 'LLM 서비스를 제공하는 회사의 표준 식별자입니다 (예: fireworks, openai).';
COMMENT ON COLUMN llm_key_config.api_key_reference IS '실제 API 키가 저장된 외부 보안 저장소(Vault, 환경변수 등)의 참조 경로 또는 식별자입니다.';
COMMENT ON COLUMN llm_key_config.model_served IS '이 API 키가 주로 사용되도록 지정된 LLM 모델 또는 모델 그룹입니다.';
COMMENT ON COLUMN llm_key_config.label IS '운영 및 관리를 위해 사람이 읽을 수 있는 형태로 부여된 이 키 설정의 고유한 이름입니다.';
COMMENT ON COLUMN llm_key_config.user_group IS '특정 사용자 그룹이나 서비스 플랜에 이 키를 우선 할당하기 위한 구분자입니다.';
COMMENT ON COLUMN llm_key_config.is_fallback_canduuidate IS '주 사용 키에 문제가 발생했을 때, 이 키를 대체 사용 후보로 고려할지 여부를 나타냅니다.';
COMMENT ON COLUMN llm_key_config.is_test_only IS '이 API 키가 테스트 목적으로만 사용되어야 하는지 여부를 나타냅니다.';
COMMENT ON COLUMN llm_key_config.is_active_overall IS '이 API 키가 현재 시스템 전체에서 활성 상태로 사용 가능한지 여부입니다.';
COMMENT ON COLUMN llm_key_config.priority IS 'LLM 키 선택 로직에서 사용될 우선순위 값입니다. 숫자가 낮을수록 우선순위가 높습니다.';
COMMENT ON COLUMN llm_key_config.rpm_limit IS 'Provuuider가 이 키에 대해 공식적으로 제한하는 분당 최대 요청 수입니다. 애플리케이션은 이 값을 참고하여 자체적으로 요청을 조절해야 합니다.';
COMMENT ON COLUMN llm_key_config.tpm_limit IS 'Provuuider가 이 키에 대해 공식적으로 제한하는 분당 최대 토큰 처리량입니다.';
COMMENT ON COLUMN llm_key_config.disabled_reason IS '키가 비활성화된 경우(is_active_overall = FALSE) 그 사유를 기록합니다.';
COMMENT ON COLUMN llm_key_config.last_error_code IS '이 키를 사용한 마지막 API 호출에서 Provuuider로부터 반환된 오류 코드입니다 (성공 시 NULL).';
COMMENT ON COLUMN llm_key_config.last_failure_at IS '이 키를 사용한 API 호출이 마지막으로 실패한 시각입니다.';
COMMENT ON COLUMN llm_key_config.last_used_at IS '이 키가 마지막으로 성공적으로 LLM API 호출에 사용된 시각입니다. 키 사용 빈도 분석 및 회전 정책에 활용될 수 있습니다.';
COMMENT ON COLUMN llm_key_config.notes IS '이 API 키 설정에 대한 추가적인 관리자 메모입니다.';
COMMENT ON COLUMN llm_key_config.created_at IS '이 API 키 설정 레코드가 데이터베이스에 처음 생성된 시각입니다.';
COMMENT ON COLUMN llm_key_config.updated_at IS '이 키 설정 정보가 마지막으로 수정된 시각입니다.';

-- 인덱스
CREATE INDEX uuidx_llm_key_config_provuuider ON llm_key_config(provuuider);
CREATE INDEX uuidx_llm_key_config_model_served ON llm_key_config(model_served);
CREATE INDEX uuidx_llm_key_config_user_group ON llm_key_config(user_group);
-- 키 선택 로직 최적화용 인덱스: 활성 상태이고, 테스트 전용이 아니며, 우선순위가 높고, 최근 사용이 적은 키 순으로 조회
CREATE INDEX uuidx_llm_key_config_selection_logic ON llm_key_config(is_active_overall, is_test_only, priority ASC, last_used_at ASC NULLS FIRST);
CREATE INDEX uuidx_llm_key_config_last_used_at ON llm_key_config(last_used_at);
-- api_key_reference 및 label은 UNIQUE 제약조건에 의해 자동으로 인덱싱됩니다.

-- updated_at 자동 갱신 트리거
-- (set_updated_at() 함수는 '00_common_functions_and_types.sql' 파일에 정의될 예정)
CREATE TRIGGER trg_set_updated_at_llm_key_config
BEFORE UPDATE ON llm_key_config
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 스케일업 고려사항 주석:
-- COMMENT ON COLUMN llm_key_config.uuid IS '(스케일업 시: 이 테이블에 대한 변경 이력을 llm_key_config_history 테이블에 기록하는 트리거 추가 고려)';
-- COMMENT ON TABLE llm_key_config IS '(스케일업 시: 키 사용량에 따른 자동 비활성화/알림 로직, llm_request_log를 집계한 avg_latency_ms, success_rate 등의 통계성 컬럼 추가 고려)';