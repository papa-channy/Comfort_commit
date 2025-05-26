-- =====================================================================================
-- 파일: 02_user_oauth.sql
-- 모듈: 01_user_module (사용자 모듈)
-- 설명: 사용자의 OAuth 소셜 연동 정보를 저장합니다.
-- 대상 DB: PostgreSQL Primary RDB (사용자 인증 데이터)
-- 파티셔닝: 없음
-- MVP 중점사항: 주요 OAuth Provuuider (Google, Kakao, GitHub, Apple) 지원, Provuuider uuid별 고유성 확보.
-- 스케일업 고려사항: 신규 Provuuider 추가 시 컬럼 확장 또는 EAV 모델로 전환 검토, RLS 적용.
-- =====================================================================================

-- 사용자 소셜 연동 정보 테이블
CREATE TABLE user_oauth (
  -- 🔗 user_info와 1:1 연결 (id 기반)
  id id PRIMARY KEY REFERENCES user_info(id) ON DELETE CASCADE,
  -- user_info 테이블의 id를 참조하며, 사용자 탈퇴 시 관련 OAuth 정보도 함께 삭제됩니다.

  -- 🟦 Google 연동 정보
  google_uuid TEXT,                                         -- Google 플랫폼에서 발급된 사용자의 고유 uuid
  google_email TEXT,                                      -- Google 계정에 등록된 이메일 (user_info.email과 다를 수 있으며, 정보 제공 용도로 사용)
  google_profile_img TEXT,                                -- Google 프로필 사진 URL (기본값은 애플리케이션 레벨에서 처리 또는 user_info.profile_img와 연동)

  -- 🟨 Kakao 연동 정보
  kakao_uuid TEXT,                                          -- Kakao 플랫폼에서 발급된 사용자의 고유 uuid
  kakao_email TEXT,                                       -- Kakao 계정에 등록된 이메일 (user_info.email과 다를 수 있음)
  kakao_profile_img TEXT,                                 -- Kakao 프로필 사진 URL

  -- ⬛ GitHub 연동 정보
  github_uuid TEXT,                                         -- GitHub 플랫폼에서 발급된 사용자의 고유 uuid
  github_email TEXT,                                      -- GitHub 계정에 등록된 이메일 (user_info.email과 다를 수 있음)
  github_profile_img TEXT,                                -- GitHub 프로필 사진 URL

  -- 🍎 Apple 연동 정보
  apple_uuid TEXT,                                          -- Apple 플랫폼에서 발급된 사용자의 고유 uuid
  apple_email TEXT,                                       -- Apple 계정에 등록된 이메일 (비공개 릴레이 이메일일 수 있음)
  apple_profile_img TEXT,                                 -- Apple 프로필 사진 URL

  -- 🕒 기록
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, -- 이 레코드가 처음 생성된 시각 (최초 연동 시점)
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP -- 이 레코드 정보가 마지막으로 수정된 시각 (trg_set_updated_at_user_oauth 트리거로 자동 관리)
);

COMMENT ON TABLE user_oauth IS '사용자의 OAuth 소셜 로그인을 위한 연동 정보를 저장합니다. 각 사용자는 여러 OAuth 제공자를 통해 계정을 연동할 수 있습니다.';
COMMENT ON COLUMN user_oauth.id IS 'user_info 테이블의 사용자 id를 참조하는 기본 키이자 외래 키입니다.';
COMMENT ON COLUMN user_oauth.google_uuid IS 'Google OAuth를 통해 얻은 사용자의 고유 식별자입니다.';
COMMENT ON COLUMN user_oauth.google_email IS 'Google 계정의 이메일 주소입니다. user_info.email과 다를 수 있습니다.';
COMMENT ON COLUMN user_oauth.google_profile_img IS 'Google 계정의 프로필 사진 URL입니다.';
COMMENT ON COLUMN user_oauth.kakao_uuid IS 'Kakao OAuth를 통해 얻은 사용자의 고유 식별자입니다.';
COMMENT ON COLUMN user_oauth.kakao_email IS 'Kakao 계정의 이메일 주소입니다.';
COMMENT ON COLUMN user_oauth.kakao_profile_img IS 'Kakao 계정의 프로필 사진 URL입니다.';
COMMENT ON COLUMN user_oauth.github_uuid IS 'GitHub OAuth를 통해 얻은 사용자의 고유 식별자입니다.';
COMMENT ON COLUMN user_oauth.github_email IS 'GitHub 계정의 이메일 주소입니다.';
COMMENT ON COLUMN user_oauth.github_profile_img IS 'GitHub 계정의 프로필 사진 URL입니다.';
COMMENT ON COLUMN user_oauth.apple_uuid IS 'Apple OAuth를 통해 얻은 사용자의 고유 식별자입니다. Apple의 비공개 이메일 릴레이 서비스 사용 여부도 고려해야 합니다.';
COMMENT ON COLUMN user_oauth.apple_email IS 'Apple 계정의 이메일 주소입니다 (비공개 릴레이 가능).';
COMMENT ON COLUMN user_oauth.apple_profile_img IS 'Apple 계정의 프로필 사진 URL입니다.';
COMMENT ON COLUMN user_oauth.created_at IS '이 소셜 연동 레코드가 데이터베이스에 처음 생성된 시각입니다.';
COMMENT ON COLUMN user_oauth.updated_at IS '이 소셜 연동 정보가 마지막으로 갱신된 시각입니다 (예: 토큰 갱신 시 연동 정보 업데이트).';

-- user_oauth 테이블 인덱스
-- 각 Provuuider uuid는 NULL이 아닐 경우 시스템 전체에서 고유해야 합니다 (다른 사용자가 동일 소셜 uuid로 중복 가입 방지).
CREATE UNIQUE INDEX uuidx_user_oauth_google_uuid ON user_oauth(google_uuid) WHERE google_uuid IS NOT NULL;
CREATE UNIQUE INDEX uuidx_user_oauth_kakao_uuid ON user_oauth(kakao_uuid) WHERE kakao_uuid IS NOT NULL;
CREATE UNIQUE INDEX uuidx_user_oauth_github_uuid ON user_oauth(github_uuid) WHERE github_uuid IS NOT NULL;
CREATE UNIQUE INDEX uuidx_user_oauth_apple_uuid ON user_oauth(apple_uuid) WHERE apple_uuid IS NOT NULL;
-- id는 PRIMARY KEY이므로 자동으로 UNIQUE 인덱스가 생성됩니다.

-- updated_at 컬럼 자동 갱신 트리거
-- (참고: set_updated_at() 함수는 '00_common_functions_and_types.sql' 파일에 최종적으로 통합 정의될 예정)
CREATE TRIGGER trg_set_updated_at_user_oauth
BEFORE UPDATE ON user_oauth
FOR EACH ROW EXECUTE FUNCTION set_updated_at();