CREATE TABLE user_info (
  id SERIAL PRIMARY KEY,
  uuid UUID DEFAULT gen_random_uuid(),            -- 외부 노출용 안전 식별자

  -- 기본 정보
  username TEXT NOT NULL,                         -- 표시명
  email TEXT UNIQUE NOT NULL,                     -- 로그인 ID
  password_hash TEXT,                             -- 비밀번호 해시 (소셜 로그인 시 NULL 가능)
  phone TEXT,
  profile_img TEXT,

  -- 인증 정보
  email_verified BOOLEAN DEFAULT FALSE,
  phone_verified BOOLEAN DEFAULT FALSE,
  two_factor_enabled BOOLEAN DEFAULT FALSE,

  -- 로그인 방식 / 소셜 연동
  login_method TEXT DEFAULT 'email',              -- email / google / kakao / github
  oauth_provider TEXT,                            -- kakao, google, github 중 실제 provider
  oauth_id TEXT,                                  -- 해당 provider의 고유 사용자 ID

  -- 추천인 코드
  referral_code TEXT UNIQUE,                      -- 본인 코드 (초대할 때 제공)
  referred_by TEXT,                               -- 추천받은 사람의 referral_code
  reward_flags TEXT[] DEFAULT '{}',               -- ex: ['no_ads', 'kakao_free_week']

  -- 계정 상태
  is_active BOOLEAN DEFAULT TRUE,
  is_suspended BOOLEAN DEFAULT FALSE,
  suspended_reason TEXT,
  last_login TIMESTAMP,

  -- 유저 속성
  user_type TEXT DEFAULT 'free',                  -- free, pro, enterprise
  roles TEXT[] DEFAULT ARRAY['user'],
  permissions JSONB,

  -- 환경 설정
  nation TEXT DEFAULT 'KR',
  timezone TEXT DEFAULT 'Asia/Seoul',
  language TEXT DEFAULT 'ko',

  -- 알림 연동
  noti_channels TEXT[],                           -- ['gmail', 'slack', 'kakao', 'discord']
  workspace TEXT,
  key_group TEXT UNIQUE,                          -- 외부 키 저장용 FK

  -- 약관 동의
  agreed_terms BOOLEAN DEFAULT FALSE,
  agreed_privacy BOOLEAN DEFAULT FALSE,
  agreed_marketing BOOLEAN DEFAULT FALSE,

  -- 기록
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


CREATE TABLE noti_group_meta (
  id SERIAL PRIMARY KEY,
  group_type TEXT NOT NULL,         -- 예: 'slack', 'kakao', 'gmail', 'discord'
  group_name TEXT NOT NULL UNIQUE,  -- 예: 'slack_team_alpha'
  description TEXT,                 -- 관리자 설명
  is_active BOOLEAN DEFAULT TRUE,   -- 비활성 그룹 필터링용
  weight INT DEFAULT 1,             -- 로드 밸런싱용 우선순위
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE user_secret (
  id SERIAL PRIMARY KEY,
  key_group TEXT NOT NULL UNIQUE,

  -- 그룹은 이제 FK로 연결
  slack_group TEXT REFERENCES noti_group_meta(group_name),
  kakao_group TEXT REFERENCES noti_group_meta(group_name),
  discord_group TEXT REFERENCES noti_group_meta(group_name),
  telegram_group TEXT REFERENCES noti_group_meta(group_name),
  gmail_group TEXT REFERENCES noti_group_meta(group_name),

  -- 실 키값들
  slack_token TEXT,
  kakao_token TEXT,
  discord_token TEXT,
  telegram_token TEXT,
  gmail_app_pw TEXT,

  google_token TEXT,
  github_token TEXT
);

CREATE TABLE user_auth_log (
  id BIGSERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES user_info(id),
  event_type TEXT,
  ip_address TEXT,
  user_agent TEXT,
  success BOOLEAN,
  created_at TIMESTAMP NOT NULL)
PARTITION BY RANGE (created_at);

CREATE TABLE user_session (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES user_info(id),
  session_id UUID DEFAULT gen_random_uuid() UNIQUE,
  
  -- 로그인 인증 정보
  access_token TEXT NOT NULL,
  refresh_token TEXT NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  last_seen TIMESTAMP,

  -- 디바이스 및 위치 정보
  device_id TEXT,                   -- 디바이스 고유 ID (ex: 브라우저 ID or UUID)
  user_agent TEXT,                  -- 브라우저/OS 정보
  ip_address TEXT,

  -- 2차 인증 관련
  two_fa_required BOOLEAN DEFAULT FALSE,
  two_fa_verified BOOLEAN DEFAULT FALSE,
  two_fa_method TEXT,              -- ex: 'sms', 'totp', 'email'
  two_fa_code TEXT,                -- 최근 발급된 2FA 코드 (임시 저장)

  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  );

CREATE TABLE user_reward_log (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES user_info(id),    -- 혜택 받은 사용자
  reward_type TEXT NOT NULL,                        -- 예: 'no_ads', 'kakao_trial'
  reward_source TEXT NOT NULL,                      -- auto / referral / manual 등
  related_code TEXT,                                -- 추천인 코드 or 관리자 지급 코드
  reward_batch_id TEXT,                             -- 캠페인 코드 or 그룹 ID
  granted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,   -- 보상 부여 일자
  redeemed_at TIMESTAMP,                            -- 실제 사용 시작 일자
  expires_at TIMESTAMP,                             -- 보상 만료 일자
  is_active BOOLEAN DEFAULT TRUE,                   -- 현재 혜택 유효 여부
  notes TEXT                                         -- 관리자 메모 (예: “2달간 미접속자 대상 지급”)
);

CREATE TABLE user_plan (
  user_id INT PRIMARY KEY REFERENCES user_info(id),

  -- 요금제 정보
  plan_type TEXT DEFAULT 'free',                -- free / pro / enterprise
  is_active BOOLEAN DEFAULT TRUE,               -- 현재 유효한 플랜인지
  auto_renew BOOLEAN DEFAULT TRUE,              -- 자동 갱신 여부

  -- 사용량 제한
  llm_quota INT DEFAULT 10000,                  -- LLM 월 호출 가능 횟수
  notif_quota INT DEFAULT 2000,                 -- 알림 발송 한도
  current_llm_usage INT DEFAULT 0,              -- 이번 달 사용량
  current_notif_usage INT DEFAULT 0,            -- 알림 사용량

  -- 기간 정보
  started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  expires_at TIMESTAMP,                         -- 유료 플랜 만료일
  next_reset DATE,                              -- 다음 사용량 초기화 날짜

  -- 부가 정보
  payment_id TEXT,                              -- 외부 결제 트랜잭션 ID
  notes TEXT                                     -- 관리자 메모
);

CREATE TABLE repo_meta (
  repo_id SERIAL PRIMARY KEY,
  repo_url TEXT NOT NULL UNIQUE,
  repo_name TEXT,
  git_provider TEXT,
  git_default_user TEXT,
  main_branch TEXT DEFAULT 'main',
  is_private BOOLEAN DEFAULT FALSE,
  visibility_scope TEXT DEFAULT 'personal',
  main_language TEXT,
  framework TEXT,
  is_monorepo BOOLEAN DEFAULT FALSE,
  has_docker BOOLEAN,
  has_tests BOOLEAN,
  file_count INT,
  folder_count INT,
  total_size_mb NUMERIC,
  commit_count INT,
  tag_count INT,
  first_commit_time TIMESTAMP,
  last_commit_time TIMESTAMP,
  has_ci_cd BOOLEAN DEFAULT FALSE,          -- .github/workflows 등 존재 여부
  test_coverage_ratio NUMERIC,             -- % 기준 정적 추정 (optional)
  has_env_file BOOLEAN DEFAULT FALSE,      -- .env 파일 포함 여부 (보안 분석)
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  deletion_flag BOOLEAN DEFAULT FALSE,
  deletion_reason TEXT,
  scheduled_for_deletion_at TIMESTAMP
);

CREATE TABLE repo_runtime_state (
  repo_id INT PRIMARY KEY REFERENCES repo_meta(repo_id) ON DELETE CASCADE,
  ssh_mode_enabled BOOLEAN DEFAULT FALSE,
  is_codespaces BOOLEAN DEFAULT FALSE,
  uses_github_cli BOOLEAN DEFAULT FALSE,
  remote_session_mode TEXT,     -- ssh / codespaces / none
  auto_commit_enabled BOOLEAN DEFAULT TRUE,
  auto_upload_enabled BOOLEAN DEFAULT TRUE,
  sync_mode TEXT DEFAULT 'manual', -- manual/cron/hook
  sync_status TEXT DEFAULT 'pending',
  disabled_reason TEXT,
  last_synced_at TIMESTAMP,
  last_commit_time TIMESTAMP,
  commit_in_progress BOOLEAN DEFAULT FALSE,
  queued_for_commit BOOLEAN DEFAULT FALSE,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  commit_blocked_until TIMESTAMP,         -- 쿨다운 구조 → 커밋 금지 시각
  next_commit_check_at TIMESTAMP         -- 다음 감지 스케줄링 용
);

CREATE TABLE repo_analysis_cache (
  repo_id INT PRIMARY KEY REFERENCES repo_meta(repo_id) ON DELETE CASCADE,
  readme_summary TEXT,
  main_modules TEXT[],  -- 주요 모듈 이름
  token_estimate INT,
  llm_model_used TEXT,  -- gpt-4o 등
  last_analysis_at TIMESTAMP,
  snapshot_version TEXT DEFAULT 'latest',
  analysis_notes TEXT
  );
ALTER TABLE repo_meta
ALTER COLUMN test_coverage_ratio DROP NOT NULL;
CREATE INDEX idx_repo_meta_last_commit ON repo_meta(last_commit_time);
CREATE INDEX idx_repo_meta_deletion_flag ON repo_meta(deletion_flag);
CREATE INDEX idx_repo_runtime_status ON repo_runtime_state(sync_status);
-- ✅ 1. 공통 트리거 함수 생성
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ✅ 2. repo_meta: updated_at 컬럼 추가 + 트리거 설정
ALTER TABLE repo_meta
ADD COLUMN updated_at TIMESTAMP;

CREATE TRIGGER trg_set_updated_at_repo_meta
BEFORE UPDATE ON repo_meta
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- ✅ 3. repo_runtime_state: DEFAULT 제거 + 트리거 설정
ALTER TABLE repo_runtime_state
ALTER COLUMN updated_at DROP DEFAULT;

CREATE TRIGGER trg_set_updated_at_runtime
BEFORE UPDATE ON repo_runtime_state
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- ✅ 4. repo_analysis_cache: updated_at 컬럼 추가 + 트리거 설정
ALTER TABLE repo_analysis_cache
ADD COLUMN updated_at TIMESTAMP;

CREATE TRIGGER trg_set_updated_at_analysis
BEFORE UPDATE ON repo_analysis_cache
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- 암호 해시 알고리즘 버전 저장
ALTER TABLE user_info ADD COLUMN password_hash_algorithm TEXT DEFAULT 'bcrypt';

-- 최근 활동 일자 저장 (휴면 계정 관리용)
ALTER TABLE user_info ADD COLUMN last_active_date DATE;

-- permissions JSONB에 인덱스 (성능 개선)
CREATE INDEX idx_user_permissions ON user_info USING gin(permissions);

-- 디바이스 타입 분리 저장
ALTER TABLE user_session ADD COLUMN device_type TEXT;

-- 만료 시간 기준 인덱스 (세션 정리용)
CREATE INDEX idx_user_session_expires_at ON user_session(expires_at);

CREATE TABLE user_plan_history (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES user_info(id),
  old_plan_type TEXT,
  new_plan_type TEXT,
  changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  changed_by TEXT,                     -- 관리자 or 시스템
  note TEXT
);

CREATE TABLE reward_batch_meta (
  batch_id TEXT PRIMARY KEY,
  description TEXT,
  created_by TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  expires_at TIMESTAMP
);

-- 임시 비활성화 타임스탬프 (로드 밸런싱 제어)
ALTER TABLE noti_group_meta ADD COLUMN temporary_disabled_until TIMESTAMP;

CREATE INDEX idx_auth_log_user_created ON user_auth_log(user_id, created_at DESC);

-- ✅ 1. 역할 기반 접근 권한 정의 테이블
CREATE TABLE repo_role_policy (
  role TEXT PRIMARY KEY,                        -- role 이름 (e.g., owner)
  can_commit BOOLEAN DEFAULT FALSE,
  can_invite BOOLEAN DEFAULT FALSE,
  can_change_settings BOOLEAN DEFAULT FALSE,
  can_generate_msg BOOLEAN DEFAULT FALSE,
  can_see_cost BOOLEAN DEFAULT FALSE,
  can_delete_repo BOOLEAN DEFAULT FALSE,
  notes TEXT
);

-- ✅ 2. 기본 권한 정책 데이터 입력
INSERT INTO repo_role_policy (role, can_commit, can_invite, can_change_settings, can_generate_msg, can_see_cost, can_delete_repo, notes)
VALUES
  ('owner',      TRUE, TRUE, TRUE, TRUE, TRUE, TRUE,    '레포의 소유자'),
  ('maintainer', TRUE, TRUE, TRUE, TRUE, TRUE, FALSE,   '관리자급 기여자'),
  ('member',     TRUE, FALSE, FALSE, TRUE, FALSE, FALSE,'일반 기여자'),
  ('viewer',     FALSE, FALSE, FALSE, FALSE, FALSE, FALSE,'읽기 전용 접근');

-- ✅ 3. 사용자–레포 연결 테이블
CREATE TABLE repo_member (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES user_info(id) ON DELETE CASCADE,
  repo_id INT NOT NULL REFERENCES repo_meta(repo_id) ON DELETE CASCADE,

  -- 역할/상태
  role TEXT DEFAULT 'member',                  -- owner / maintainer / member / viewer
  is_owner BOOLEAN DEFAULT FALSE,              -- 명시적 소유자 표시
  is_active BOOLEAN DEFAULT TRUE,              -- soft delete 방식
  join_status TEXT DEFAULT 'approved',         -- invited / pending / approved / rejected
  invited_by INT REFERENCES user_info(id),     -- 초대한 사용자
  joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP
);

-- ✅ 4. 트리거 함수가 없다면 먼저 생성
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ✅ 5. repo_member에 트리거 연결
CREATE TRIGGER trg_set_updated_at_repo_member
BEFORE UPDATE ON repo_member
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- ✅ 6. 인덱스 추가 (트래픽 최적화용)
CREATE INDEX idx_repo_member_user_repo ON repo_member(user_id, repo_id);
CREATE INDEX idx_repo_member_role_status ON repo_member(role, join_status);

