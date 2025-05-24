-- ENUM 타입 정의 (user_info 테이블 생성 전에 실행)
CREATE TYPE user_account_type AS ENUM ('personal', 'team', 'org');

CREATE TABLE user_info (
 -- 🆔 기본 식별자
 id SERIAL PRIMARY KEY,
 uuid UUID UNIQUE DEFAULT gen_random_uuid(),

 account_links JSONB DEFAULT '{}'::JSONB,

 -- 👤 사용자 기본 정보
 account_type user_account_type DEFAULT 'personal', -- ENUM 타입으로 변경
 username TEXT NOT NULL,
 email TEXT UNIQUE NOT NULL,
 phone TEXT, -- 현재 TEXT 타입 유지, 애플리케이션 레벨에서 처리

 oauth_links JSONB DEFAULT '{}'::JSONB, -- UI 최적화를 위해 유지
 profile_img TEXT,

 -- ✅ 인증 상태
 email_verified BOOLEAN DEFAULT FALSE,
 phone_verified BOOLEAN DEFAULT FALSE,
 two_factor_enabled BOOLEAN DEFAULT FALSE,

 -- 🛡️ 계정 상태 관리
 is_active BOOLEAN DEFAULT TRUE,
 is_suspended BOOLEAN DEFAULT FALSE,
 suspended_reason TEXT,
 last_login TIMESTAMP,
 last_active_date DATE,

 -- 🌐 환경 설정
 nation TEXT DEFAULT 'KR',
 timezone TEXT DEFAULT 'Asia/Seoul',
 language TEXT DEFAULT 'ko',

 -- 📜 약관 동의
 agreed_terms BOOLEAN DEFAULT FALSE,
 agreed_privacy BOOLEAN DEFAULT FALSE,
 agreed_marketing BOOLEAN DEFAULT FALSE,

 -- 🕒 기록
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 updated_at TIMESTAMP
);

-- 🔍 인덱스: 조회/필터링 최적화 (기존과 동일)
CREATE INDEX idx_user_username ON user_info(username);
CREATE INDEX idx_user_account_type ON user_info(account_type);
CREATE INDEX idx_user_is_active ON user_info(is_active);
CREATE INDEX idx_user_last_login ON user_info(last_login DESC);
CREATE UNIQUE INDEX idx_user_email ON user_info(email);
CREATE UNIQUE INDEX idx_user_uuid ON user_info(uuid);
CREATE INDEX idx_user_phone ON user_info(phone);

-- 트리거 (기존과 동일)
CREATE TRIGGER set_updated_at_user_info
BEFORE UPDATE ON user_info
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
-- 📄 공통 함수 정의 (필요시 테이블 생성 전 실행)
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 👤 사용자 계정 유형 ENUM 타입 정의
CREATE TYPE user_account_type AS ENUM ('personal', 'team', 'org');

-- 1. 사용자 기본 정보 테이블
CREATE TABLE user_info (
  -- 🆔 기본 식별자
  id SERIAL PRIMARY KEY,
  uuid UUID UNIQUE DEFAULT gen_random_uuid(),

  account_links JSONB DEFAULT '{}'::JSONB,

  -- 👤 사용자 기본 정보
  account_type user_account_type DEFAULT 'personal', -- ENUM 타입 적용
  username TEXT NOT NULL,
  email TEXT UNIQUE NOT NULL,
  phone TEXT, -- 애플리케이션 레벨에서 유효성 검증/정규화

  oauth_links JSONB DEFAULT '{}'::JSONB, -- UI 최적화용 캐시성 정보
  profile_img TEXT,

  -- ✅ 인증 상태
  email_verified BOOLEAN DEFAULT FALSE,
  phone_verified BOOLEAN DEFAULT FALSE,
  two_factor_enabled BOOLEAN DEFAULT FALSE,

  -- 🛡️ 계정 상태 관리
  is_active BOOLEAN DEFAULT TRUE,
  is_suspended BOOLEAN DEFAULT FALSE,
  suspended_reason TEXT,
  last_login TIMESTAMP,
  last_active_date DATE,

  -- 🌐 환경 설정
  nation TEXT DEFAULT 'KR',
  timezone TEXT DEFAULT 'Asia/Seoul',
  language TEXT DEFAULT 'ko',

  -- 📜 약관 동의
  agreed_terms BOOLEAN DEFAULT FALSE,
  agreed_privacy BOOLEAN DEFAULT FALSE,
  agreed_marketing BOOLEAN DEFAULT FALSE,

  -- 🕒 기록
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP
);

-- user_info 테이블 인덱스
CREATE INDEX idx_user_username ON user_info(username);
CREATE INDEX idx_user_account_type ON user_info(account_type);
CREATE INDEX idx_user_is_active ON user_info(is_active);
CREATE INDEX idx_user_last_login ON user_info(last_login DESC);
CREATE UNIQUE INDEX idx_user_email ON user_info(email);
CREATE UNIQUE INDEX idx_user_uuid ON user_info(uuid);
CREATE INDEX idx_user_phone ON user_info(phone);

-- user_info 테이블 updated_at 트리거
CREATE TRIGGER set_updated_at_user_info
BEFORE UPDATE ON user_info
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 2. 사용자 소셜 연동 정보 테이블
CREATE TABLE user_oauth (
  -- 🔗 user_info와 1:1 연결 (uuid 기반)
  uuid UUID PRIMARY KEY REFERENCES user_info(uuid) ON DELETE CASCADE,

  -- 🟦 Google 연동 정보
  google_id TEXT,
  google_email TEXT,
  google_profile_img TEXT DEFAULT '/static/img/avatar-google.png',

  -- 🟨 Kakao 연동 정보
  kakao_id TEXT,
  kakao_email TEXT,
  kakao_profile_img TEXT DEFAULT '/static/img/avatar-kakao.png',

  -- ⬛ GitHub 연동 정보
  github_id TEXT,
  github_email TEXT,
  github_profile_img TEXT DEFAULT '/static/img/avatar-github.png',

  -- 🍎 Apple 연동 정보 (추가)
  apple_id TEXT,
  apple_email TEXT,
  apple_profile_img TEXT DEFAULT '/static/img/avatar-apple.png',

  -- 🕒 기록
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP
);

-- user_oauth 테이블 인덱스 (각 Provider ID는 NULL이 아닐 경우 고유)
CREATE UNIQUE INDEX idx_oauth_google_id ON user_oauth(google_id) WHERE google_id IS NOT NULL;
CREATE UNIQUE INDEX idx_oauth_kakao_id ON user_oauth(kakao_id) WHERE kakao_id IS NOT NULL;
CREATE UNIQUE INDEX idx_oauth_github_id ON user_oauth(github_id) WHERE github_id IS NOT NULL;
CREATE UNIQUE INDEX idx_oauth_apple_id ON user_oauth(apple_id) WHERE apple_id IS NOT NULL;

-- user_oauth 테이블 updated_at 트리거
CREATE TRIGGER set_updated_at_user_oauth
BEFORE UPDATE ON user_oauth
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TABLE user_session (
 -- 🆔 세션 식별 정보
 id SERIAL PRIMARY KEY,
 user_id INT NOT NULL REFERENCES user_info(id) ON DELETE CASCADE, -- Option A: user_info.id 참조
 session_id UUID UNIQUE DEFAULT gen_random_uuid(),
 -- 🔐 인증 토큰 정보 (MVP: 앱 레벨 암호화 후 DB 저장)
 access_token TEXT NOT NULL,
 refresh_token TEXT NOT NULL,
 expires_at TIMESTAMP NOT NULL,
 last_seen TIMESTAMP,
 -- 💻 디바이스 및 브라우저 정보
 device_id TEXT, -- 클라이언트 생성 고유 ID
 user_agent TEXT,
 os TEXT,
 browser TEXT,
 ip_address TEXT,
 location TEXT,

 -- 🔒 2차 인증 (2FA)
 two_fa_required BOOLEAN DEFAULT FALSE,
 two_fa_verified BOOLEAN DEFAULT FALSE,
 two_fa_method TEXT,
 two_fa_code TEXT,
 two_fa_expires_at TIMESTAMP,

 -- 🕒 시스템 기록
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 updated_at TIMESTAMP -- 트리거로 자동 갱신
);

-- 필수 인덱스
CREATE INDEX idx_user_session_user_id ON user_session(user_id);
CREATE INDEX idx_user_session_last_seen ON user_session(last_seen DESC);
CREATE INDEX idx_user_session_expires_at ON user_session(expires_at);
-- session_id는 UNIQUE 제약으로 자동 인덱싱

-- updated_at 자동 갱신 트리거 (user_info의 set_updated_at() 함수 재활용)
CREATE TRIGGER set_updated_at_user_session
BEFORE UPDATE ON user_session
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 세션 만료 정리용 함수 (이미 정의됨, 주기적 실행 필요)
-- CREATE OR REPLACE FUNCTION delete_expired_sessions() ...
