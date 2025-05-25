-- =====================================================================================
-- 파일: 03_user_session.sql
-- 모듈: 01_user_module (사용자 모듈)
-- 설명: 사용자의 로그인 세션 정보를 관리합니다.
-- 대상 DB: PostgreSQL Primary RDB (사용자 인증/세션 데이터)
-- 파티셔닝: 고려 가능 (오래된 세션 데이터는 삭제 또는 아카이빙, 또는 last_seen_at 기준으로 월별 파티셔닝 - 스케일업 시)
-- MVP 중점사항: 핵심 세션 정보, 토큰 참조 관리, 필수 인덱스, 만료 세션 정리 함수.
-- 스케일업 고려사항: 실제 토큰 외부 저장소(Redis) 필수화, RLS, 파티셔닝, 고급 보안 인덱스 추가.
-- =====================================================================================

-- 사용자 세션 정보 테이블
CREATE TABLE user_session (
  -- 🆔 세션 식별 정보
  id SERIAL PRIMARY KEY,                                  -- 내부 자동 증가 ID
  user_uuid UUID NOT NULL,                                -- 사용자 식별자 (user_info.uuid 참조)
  session_id UUID UNIQUE NOT NULL DEFAULT gen_random_uuid(),-- 세션 고유 식별자 (토큰 추적/무효화 시 사용)

  -- 🔐 인증 토큰 정보
  -- MVP에서는 앱 레벨 암호화 후 DB에 저장할 수 있으나,
  -- 스케일업 시 실제 토큰 값은 외부 저장소(예: Redis)에 저장하고, 여기서는 해당 참조 ID 또는 해시값을 저장하는 것을 강력히 권장합니다.
  access_token_ref TEXT NOT NULL,                         -- Access Token 참조 ID 또는 해시 (실제 토큰 아님)
  refresh_token_ref TEXT NOT NULL,                        -- Refresh Token 참조 ID 또는 해시 (실제 토큰 아님)
  expires_at TIMESTAMP NOT NULL,                          -- 토큰 만료 시각 (주로 Access Token 기준)
  last_seen_at TIMESTAMP,                                 -- 마지막 요청 시각 (세션 활동 추적용)

  -- 💻 디바이스 및 브라우저 정보
  device_id TEXT,                                         -- 클라이언트(브라우저/앱)에서 생성/관리하는 고유 ID (예: localStorage UUID)
  user_agent TEXT,                                        -- 전체 브라우저/OS 문자열
  os_name TEXT,                                           -- 운영체제 이름 (예: Windows, Android, iOS)
  browser_name TEXT,                                      -- 브라우저 종류 (예: Chrome, Safari)
  ip_address TEXT,                                        -- 접속 IP 주소 (보안 위협 탐지, 위치 추정 등)
  location_info TEXT,                                     -- 추정 지역 정보 (GeoIP 기반 국가/도시 등, 예: "KR, Seoul")

  -- 🔒 2차 인증 (2FA) 관련 정보
  two_fa_required_at_login BOOLEAN DEFAULT FALSE,         -- 해당 세션 생성(로그인) 시 2FA가 요구되었는지 여부
  two_fa_verified_in_session BOOLEAN DEFAULT FALSE,       -- 이 세션 내에서 2FA 인증이 성공적으로 완료되었는지 여부
  two_fa_method_used TEXT,                                -- 사용된 2FA 방식 (예: 'sms', 'email', 'totp', 'authenticator_app'). 1회용 코드 자체는 DB에 저장하지 않음.

  -- 🕒 시스템 기록
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, -- 세션 생성 시각
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP -- 세션 정보 갱신 시각 (trg_set_updated_at_user_session 트리거로 자동 관리)
);

COMMENT ON TABLE user_session IS '사용자의 로그인 세션 정보를 저장하며, 인증 토큰 참조, 접속 환경, 2FA 상태 등을 관리합니다.';
COMMENT ON COLUMN user_session.user_uuid IS '세션 소유자인 사용자의 UUID (user_info.uuid 참조)입니다.';
COMMENT ON COLUMN user_session.session_id IS '각 세션을 고유하게 식별하는 UUID로, 특정 세션 무효화 등에 사용됩니다.';
COMMENT ON COLUMN user_session.access_token_ref IS '외부 저장소(예: Redis)에 저장된 Access Token의 참조 ID 또는 식별 가능한 해시값입니다. 실제 토큰 값이 아닙니다.';
COMMENT ON COLUMN user_session.refresh_token_ref IS '외부 저장소에 저장된 Refresh Token의 참조 ID 또는 식별 가능한 해시값입니다. 실제 토큰 값이 아닙니다.';
COMMENT ON COLUMN user_session.expires_at IS 'Access Token의 만료 시각입니다.';
COMMENT ON COLUMN user_session.last_seen_at IS '해당 세션으로 마지막 활동이 감지된 시각입니다.';
COMMENT ON COLUMN user_session.device_id IS '세션이 발생한 클라이언트 기기의 고유 식별자입니다 (예: 브라우저 fingerprint, 앱 인스턴스 ID).';
COMMENT ON COLUMN user_session.two_fa_method_used IS '사용자가 이 세션에서 사용한 2단계 인증 방식입니다. 1회용 코드 자체는 DB에 저장하지 않습니다.';
COMMENT ON COLUMN user_session.updated_at IS '이 세션 정보가 마지막으로 갱신된 시각입니다.';

-- user_session 테이블과 user_info 테이블 간의 외래 키 제약 조건
ALTER TABLE user_session
ADD CONSTRAINT fk_user_session_user_uuid
FOREIGN KEY (user_uuid) REFERENCES user_info(uuid) ON DELETE CASCADE;
COMMENT ON CONSTRAINT fk_user_session_user_uuid ON user_session IS 'user_info 테이블의 사용자 UUID를 참조합니다. 사용자 삭제 시 관련 세션도 함께 삭제됩니다.';

-- user_session 테이블 필수 인덱스
CREATE INDEX idx_user_session_user_uuid ON user_session(user_uuid);
CREATE INDEX idx_user_session_last_seen_at ON user_session(last_seen_at DESC NULLS LAST);
CREATE INDEX idx_user_session_expires_at ON user_session(expires_at);
-- session_id는 UNIQUE 제약조건에 의해 자동으로 인덱싱됩니다.

-- updated_at 컬럼 자동 갱신 트리거
-- (set_updated_at() 함수는 '00_common_functions_and_types.sql' 파일에 정의될 예정)
CREATE TRIGGER trg_set_updated_at_user_session
BEFORE UPDATE ON user_session
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 세션 만료 정리용 함수는 '00_common_functions_and_types.sql'에 정의될 예정이며,
-- pg_cron 등을 통해 주기적으로 실행되어야 합니다.
-- 예시: SELECT cron.schedule('delete-expired-sessions-hourly', '0 * * * *', 'SELECT delete_expired_sessions();');