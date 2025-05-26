-- =====================================================================================
-- 파일: 01_user_info.sql
-- 모듈: 01_user_module (사용자 모듈)
-- 설명: 모든 사용자의 기본 정보를 저장합니다.
-- 대상 DB: PostgreSQL Primary RDB (핵심 사용자 데이터)
-- 파티셔닝: 없음 (직접 접근, 일반적으로 시계열 또는 로그와 같은 형태가 아님)
-- MVP 중점사항: 핵심 필드, 공통 ENUM 타입 참조, 기본 인덱스, 약관 동의 시각 기록.
-- 스케일업 고려사항: 데이터 접근 제어를 위한 RLS(Row-Level Security), email/phone CITEXT 타입 전환.
-- =====================================================================================

-- 사용자 정보 기본 테이블
CREATE TABLE user_info (
  -- 🆔 기본 식별자
  uuid SERIAL PRIMARY KEY,                                  -- 내부 자동 증가 uuid (참조용)
  id id UNIQUE NOT NULL DEFAULT gen_random_id(),    -- 외부 공개용 고유 식별자 (노출 가능, 충돌 방지)

  account_links JSONB DEFAULT '{}'::JSONB,                -- 사용자의 다른 내부 서비스/모듈 계정 연결 정보 (예: {"team_id": "some-team-id", "organization_uuid": "org-uuid-123"})
  oauth_links JSONB DEFAULT '{}'::JSONB,                  -- 소셜 연동 상태 플래그 및 간략 정보 (UI 최적화용 캐시, 예: {"google_linked": true, "kakao_nickname": "라이언"})

  -- 👤 사용자 기본 정보
  account_type user_account_type_enum DEFAULT 'personal',      -- 계정 유형 (00_common_functions_and_types.sql 정의된 ENUM 타입 적용)
  username TEXT NOT NULL,                                 -- 사용자 표시명 (닉네임 또는 이름, 로그인 시 사용될 수도 있음, 앱 레벨에서 고유성 및 정책 관리)
  email TEXT UNIQUE NOT NULL,                             -- 이메일 주소 (로그인 uuid, 고유). (스케일업 시: CITEXT 타입으로 대소문자 구분 없는 고유성 검토)
  phone TEXT UNIQUE,                                      -- 전화번호 (선택사항, 인증 또는 알림 용도, 앱 레벨에서 고유성 관리). (스케일업 시: CITEXT 타입 및 E.164 정규화 검토)
  profile_img TEXT,                                       -- 사용자 프로필 사진 경로 또는 URL (NULL 가능)

  -- ✅ 인증 상태
  email_verified_at TIMESTAMP,                            -- 이메일 인증 완료 시각 (NULL이면 미인증)
  phone_verified_at TIMESTAMP,                            -- 전화번호 인증 완료 시각 (NULL이면 미인증)
  two_factor_enabled BOOLEAN DEFAULT FALSE,               -- 2단계 인증 활성화 여부

  -- 🛡️ 계정 상태 관리
  is_active BOOLEAN DEFAULT TRUE,                         -- 계정 활성 상태 (비활성화 시 로그인 차단)
  is_suspended BOOLEAN DEFAULT FALSE,                     -- 계정 정지 여부
  suspended_reason TEXT,                                  -- 정지 사유 (관리자 메모용)
  last_login_at TIMESTAMP,                                -- 마지막 로그인 시각 (보안 및 통계용)
  last_active_date DATE,                                  -- 마지막 활동 일자 (휴면 계정 감지용, 일 단위 업데이트)

  -- 🌐 환경 설정
  nation TEXT DEFAULT 'KR',                               -- 국가 코드 (ISO-3166 Alpha-2, 기본값 KR)
  timezone TEXT DEFAULT 'Asia/Seoul',                     -- 시간대 (IANA 기준, 기본: 서울)
  language TEXT DEFAULT 'ko',                             -- 기본 UI 언어 (ko, en 등)

  -- 📜 약관 동의 (인수인계 문서 Ver.2 반영: 동의 시각 기록)
  agreed_terms_at TIMESTAMP,                              -- 서비스 약관 동의 시각 (NULL이면 미동의)
  agreed_privacy_at TIMESTAMP,                            -- 개인정보 수집 동의 시각 (NULL이면 미동의)
  agreed_marketing_at TIMESTAMP,                          -- 마케팅 수신 동의 시각 (NULL이면 미동의 또는 동의 철회)

  -- 🕒 기록
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, -- 사용자 등록 시각
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP -- 정보 갱신 시각 (trg_set_updated_at_user_info 트리거로 자동 관리)
);

COMMENT ON TABLE user_info IS '사용자의 핵심 프로필 정보를 저장합니다.';
COMMENT ON COLUMN user_info.uuid IS '내부 시스템에서 사용하는 자동 증가 사용자 uuid입니다.';
COMMENT ON COLUMN user_info.id IS '외부 시스템 연동 또는 API 노출 시 사용되는 고유 사용자 식별자입니다.';
COMMENT ON COLUMN user_info.account_links IS '사용자의 다른 내부 서비스/모듈 계정 연결 정보입니다. 예: {"team_id": "some-team-id"}';
COMMENT ON COLUMN user_info.oauth_links IS '소셜 연동 상태 플래그 및 간략한 캐시 정보입니다. UI 최적화에 사용될 수 있습니다. 예: {"google_linked": true, "kakao_profile_image_url": "..."}';
COMMENT ON COLUMN user_info.account_type IS '사용자 계정의 유형을 나타냅니다 (00_common_functions_and_types.sql 정의된 user_account_type_enum 값).';
COMMENT ON COLUMN user_info.username IS '사용자 표시명 (닉네임 또는 이름)입니다. 앱 레벨에서 고유성 및 사용 정책이 관리될 수 있습니다.';
COMMENT ON COLUMN user_info.email IS '사용자의 기본 이메일 주소로, 로그인 uuid 및 주요 소통 수단으로 사용됩니다. 시스템 내에서 고유해야 합니다.';
COMMENT ON COLUMN user_info.phone IS '사용자의 전화번호입니다. 선택 사항이며, 인증 또는 알림 용도로 사용될 수 있습니다. 앱 레벨에서 고유성이 관리될 수 있습니다.';
COMMENT ON COLUMN user_info.profile_img IS '사용자 프로필 사진의 경로 또는 URL입니다. NULL일 수 있습니다.';
COMMENT ON COLUMN user_info.email_verified_at IS '사용자의 이메일 주소가 인증된 시각입니다. NULL인 경우 아직 인증되지 않았음을 의미합니다.';
COMMENT ON COLUMN user_info.phone_verified_at IS '사용자의 전화번호가 인증된 시각입니다. NULL인 경우 아직 인증되지 않았음을 의미합니다.';
COMMENT ON COLUMN user_info.two_factor_enabled IS '사용자가 2단계 인증(Two-Factor Authentication)을 활성화했는지 여부입니다.';
COMMENT ON COLUMN user_info.is_active IS '계정이 현재 활성 상태인지 여부를 나타냅니다. 비활성 계정은 서비스 로그인이 제한될 수 있습니다.';
COMMENT ON COLUMN user_info.is_suspended IS '계정이 운영 정책 위반 등으로 인해 일시 정지된 상태인지 여부입니다.';
COMMENT ON COLUMN user_info.suspended_reason IS '계정이 정지된 경우, 그 사유에 대한 관리자 또는 시스템 메모입니다.';
COMMENT ON COLUMN user_info.last_login_at IS '사용자가 마지막으로 서비스에 성공적으로 로그인한 시각입니다.';
COMMENT ON COLUMN user_info.last_active_date IS '사용자의 마지막 활동 일자로, 휴면 계정 처리 등의 기준으로 사용될 수 있습니다.';
COMMENT ON COLUMN user_info.nation IS '사용자의 국가 코드입니다 (ISO 3166-1 Alpha-2 기준, 예: KR, US).';
COMMENT ON COLUMN user_info.timezone IS '사용자가 선호하는 시간대입니다 (IANA Time Zone Database 기준, 예: Asia/Seoul).';
COMMENT ON COLUMN user_info.language IS '사용자가 선호하는 서비스 UI 언어입니다 (예: ko, en).';
COMMENT ON COLUMN user_info.agreed_terms_at IS '서비스 이용약관에 동의한 시각입니다. NULL인 경우 약관에 동의하지 않았음을 의미합니다.';
COMMENT ON COLUMN user_info.agreed_privacy_at IS '개인정보 수집 및 이용에 동의한 시각입니다. NULL인 경우 동의하지 않았음을 의미합니다.';
COMMENT ON COLUMN user_info.agreed_marketing_at IS '마케팅 정보 수신에 동의한 시각입니다. NULL인 경우 동의하지 않았거나 동의를 철회했음을 의미합니다.';
COMMENT ON COLUMN user_info.created_at IS '해당 사용자 정보 레코드가 데이터베이스에 처음 생성된 시각입니다.';
COMMENT ON COLUMN user_info.updated_at IS '해당 사용자 정보 로우가 마지막으로 수정된 시각입니다.';

-- user_info 테이블 인덱스
CREATE INDEX uuidx_user_username ON user_info(username); -- 사용자명 검색을 위해 (로그인 시 username 사용 가능성 고려)
CREATE INDEX uuidx_user_account_type ON user_info(account_type);
CREATE INDEX uuidx_user_is_active ON user_info(is_active); -- 활성 사용자 필터링
CREATE INDEX uuidx_user_last_login_at ON user_info(last_login_at DESC NULLS LAST); -- 최근 로그인 사용자 조회
-- email 및 id 컬럼은 UNIQUE 제약조건에 의해 자동으로 인덱싱됩니다.
CREATE INDEX uuidx_user_phone ON user_info(phone) WHERE phone IS NOT NULL; -- 전화번호 검색 (NULL 제외)

-- updated_at 컬럼 자동 갱신 트리거
-- (set_updated_at() 함수는 '00_common_functions_and_types.sql' 파일에 정의될 예정)
CREATE TRIGGER trg_set_updated_at_user_info
BEFORE UPDATE ON user_info
FOR EACH ROW EXECUTE FUNCTION set_updated_at();