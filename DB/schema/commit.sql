CREATE TABLE user_info (
  -- 🆔 기본 식별자
  id SERIAL PRIMARY KEY,                                -- 내부 고유 ID (Auto Increment, 참조 용)
  uuid UUID UNIQUE DEFAULT gen_random_uuid(),           -- 외부 공개용 식별자 (노출 가능, 충돌 방지 목적)

  account_links JSONB DEFAULT '{}'::JSONB,              -- 외부 서비스 연동 메타 정보 (ex: {"slack":"team1", "notion":"db_3"})

  -- 👤 사용자 기본 정보
  account_type TEXT DEFAULT 'personal',                 -- 계정 유형: personal(개인), team, org 등
  username TEXT NOT NULL,                               -- 사용자 표시명 (닉네임 또는 이름)
  email TEXT UNIQUE NOT NULL,                           -- 이메일 주소 (로그인 ID, 고유)
  phone TEXT,                                            -- 전화번호 (선택사항, 인증 또는 알림 용도)

  oauth_links JSONB DEFAULT '{}'::JSONB,                -- 소셜 연동 여부 (ex: {"google": true, "kakao": false})
  profile_img TEXT,                                     -- 사용자 프로필 사진 경로 (null 가능)

  -- ✅ 인증 상태
  email_verified BOOLEAN DEFAULT FALSE,                 -- 이메일 인증 완료 여부
  phone_verified BOOLEAN DEFAULT FALSE,                 -- 전화번호 인증 완료 여부
  two_factor_enabled BOOLEAN DEFAULT FALSE,             -- 2단계 인증 활성화 여부

  -- 🛡️ 계정 상태 관리
  is_active BOOLEAN DEFAULT TRUE,                       -- 계정 활성 상태 (비활성화 시 로그인 차단)
  is_suspended BOOLEAN DEFAULT FALSE,                   -- 계정 정지 여부
  suspended_reason TEXT,                                -- 정지 사유 (관리자 메모용)
  last_login TIMESTAMP,                                 -- 마지막 로그인 시각 (보안 및 통계용)
  last_active_date DATE,                                -- 마지막 활동 일자 (휴면 계정 감지용)

  -- 🌐 환경 설정
  nation TEXT DEFAULT 'KR',                             -- 국가 코드 (ISO-3166, 기본값 KR)
  timezone TEXT DEFAULT 'Asia/Seoul',                   -- 시간대 (IANA 기준, 기본: 서울)
  language TEXT DEFAULT 'ko',                           -- 기본 UI 언어 (ko, en 등)

  -- 📜 약관 동의
  agreed_terms BOOLEAN DEFAULT FALSE,                   -- 서비스 약관 동의 여부
  agreed_privacy BOOLEAN DEFAULT FALSE,                 -- 개인정보 수집 동의 여부
  agreed_marketing BOOLEAN DEFAULT FALSE,               -- 마케팅 수신 동의 여부

  -- 🕒 기록
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,       -- 사용자 등록 시각
  updated_at TIMESTAMP                                  -- 정보 갱신 시각 (트리거 또는 수동 업데이트)
);

-- 🔍 인덱스: 조회/필터링 최적화
CREATE INDEX idx_user_username ON user_info(username);              -- username 기반 검색
CREATE INDEX idx_user_account_type ON user_info(account_type);      -- 계정 유형 필터링
CREATE INDEX idx_user_is_active ON user_info(is_active);            -- 활성화 여부 필터링
CREATE INDEX idx_user_last_login ON user_info(last_login DESC);     -- 최근 로그인 사용자 조회

CREATE TABLE user_oauth (
  -- 🔗 user_info와 1:1 연결 (uuid 기반)
  uuid UUID PRIMARY KEY REFERENCES user_info(uuid) ON DELETE CASCADE,
  -- user_info 삭제 시 연동 정보도 함께 삭제됨

  -- 🟦 Google 연동 정보
  google_id TEXT,                                                -- Google 플랫폼의 사용자 ID
  google_email TEXT,                                             -- 연동된 구글 이메일
  google_profile_img TEXT DEFAULT '/static/img/avatar-google.png', -- 구글 프로필 사진 (없을 시 기본)

  -- 🟨 Kakao 연동 정보
  kakao_id TEXT,                                                 -- Kakao 플랫폼 사용자 ID
  kakao_email TEXT,                                              -- 연동된 카카오 이메일
  kakao_profile_img TEXT DEFAULT '/static/img/avatar-kakao.png', -- 카카오 기본 프로필 사진

  -- ⬛ GitHub 연동 정보
  github_id TEXT,                                                -- GitHub 사용자 ID
  github_email TEXT,                                             -- 연동된 깃허브 이메일
  github_profile_img TEXT DEFAULT '/static/img/avatar-github.png', -- 기본 GitHub 이미지

  -- 🕒 기록
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,                -- 레코드 생성 시각
  updated_at TIMESTAMP                                           -- 마지막 갱신 시각
);

-- 🔍 인덱스: 소셜 계정 기반 빠른 탐색
CREATE INDEX idx_user_oauth_google_id ON user_oauth(google_id);         -- Google ID 중복 여부 확인용
CREATE INDEX idx_user_oauth_kakao_id ON user_oauth(kakao_id);           -- Kakao ID 빠른 검색
CREATE INDEX idx_user_oauth_github_id ON user_oauth(github_id);         -- GitHub ID 중복 감지
CREATE INDEX idx_user_oauth_created_at ON user_oauth(created_at DESC);  -- 최근 연동 순 정렬
CREATE INDEX idx_user_oauth_updated_at ON user_oauth(updated_at DESC);  -- 최근 갱신 순 정렬

CREATE TABLE user_session (
  -- 🆔 세션 식별 정보
  id SERIAL PRIMARY KEY,                                       -- 고유 세션 행 ID (자동 증가)
  user_id INT NOT NULL REFERENCES user_info(id),               -- 내부 계정 ID (개별 로그인 계정 기준)
  session_id UUID UNIQUE DEFAULT gen_random_uuid(),            -- 세션 고유 식별자 (토큰 추적/무효화 시 사용됨)

  -- 🔐 인증 토큰 정보
  access_token TEXT NOT NULL,                                  -- Access Token (로그인 인증용, 암호화 or ID 저장 권장)
  refresh_token TEXT NOT NULL,                                 -- Refresh Token (재발급용, 암호화 필수)
  expires_at TIMESTAMP NOT NULL,                               -- 토큰 만료 시각 (Access Token 기준)
  last_seen TIMESTAMP,                                         -- 마지막 요청 시각 (세션 활동 추적용)

  -- 💻 디바이스 및 브라우저 정보
  device_id TEXT,                                              -- 클라이언트 고유 ID (UUID, localStorage 기반)
  user_agent TEXT,                                             -- 전체 브라우저/OS 문자열 (예: Mozilla/5.0 ...)
  os TEXT,                                                     -- 운영체제 (Windows, Android, iOS 등)
  browser TEXT,                                                -- 브라우저 종류 (Chrome, Safari 등)
  ip_address TEXT,                                             -- 접속 IP (보안 위협 탐지, 위치 추정 등)
  location TEXT,                                               -- 추정 지역 정보 (GeoIP 기반 국가/도시)

  -- 🔒 2차 인증 (2FA)
  two_fa_required BOOLEAN DEFAULT FALSE,                       -- 해당 세션에서 2FA 요구 여부
  two_fa_verified BOOLEAN DEFAULT FALSE,                       -- 2FA 인증 완료 여부
  two_fa_method TEXT,                                          -- 인증 방식 (sms / email / totp)
  two_fa_code TEXT,                                            -- 발급된 인증 코드 (1회용, 임시 저장)
  two_fa_expires_at TIMESTAMP,                                -- 인증 코드 만료 시각 (TTL 판단용)

  -- 🕒 시스템 기록
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,              -- 세션 생성 시각
  updated_at TIMESTAMP                                         -- 갱신 시각 (세션 연장 등)
);

-- 기본 인덱스
CREATE INDEX idx_user_session_user_id ON user_session(user_id);
CREATE INDEX idx_user_session_last_seen ON user_session(last_seen DESC);

-- 선택적 보안 인덱스
-- CREATE INDEX idx_user_session_ip_address ON user_session(ip_address);
-- CREATE INDEX idx_user_session_two_fa_verified ON user_session(two_fa_verified);

CREATE TABLE user_notification_pref (
  -- 🆔 식별자
  id SERIAL PRIMARY KEY,                                       -- 고유 설정 행 ID

  uuid UUID NOT NULL REFERENCES user_info(uuid) ON DELETE CASCADE,  
  -- 알림 설정을 가진 사용자 (1:1 관계, 삭제 시 연쇄 삭제)

  -- 📌 알림 범위 및 유형 설정
  noti_scope TEXT[] DEFAULT ARRAY['personal'],                 -- 알림 적용 범위 (예: personal / team / org / admin 등)
  noti_type TEXT[] DEFAULT ARRAY['generic_link', 'commit_yn'],-- 알림 종류 (커밋 여부, 링크 등 분류)

  -- 📢 알림 채널 주소 설정 (NULL이면 미연동 상태)
  gmail TEXT DEFAULT 'example@gmail.com',                      -- Gmail 주소 (기본값 필수, NULL 불가)
  slack TEXT DEFAULT NULL,                                     -- Slack Webhook URL
  kakao TEXT DEFAULT NULL,                                     -- 카카오톡 ID 또는 전화번호
  discord TEXT DEFAULT NULL,                                   -- Discord Webhook URL
  telegram TEXT DEFAULT NULL,                                  -- Telegram chat_id 또는 handle
  app_push TEXT DEFAULT NULL,                                  -- 앱 푸시용 FCM token 또는 기기 ID

  -- 🔄 자동 트리거 (작업/알림 시작 조건)
  task_trigger TEXT DEFAULT 'vscode_start',                    -- 작업 시작 조건 (예: VSCode 실행 시)
  noti_trigger TEXT DEFAULT 'vscode_close',                    -- 알림 발송 시점 조건 (예: 종료 시점)

  -- 🔕 조용한 시간 설정 (해당 시간대엔 알림 비활성화)
  quiet_time_start TIME,                                       -- 알림 차단 시작 시각 (예: 22:00)
  quiet_time_end TIME,                                         -- 알림 재개 시각 (예: 08:00)

  -- 🚫 전체 알림 차단 여부
  is_enabled BOOLEAN DEFAULT TRUE,                             -- 전체 알림 허용 여부 (False면 모두 비활성화)

  -- 🕒 기록
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,              -- 설정 생성 시각
  updated_at TIMESTAMP                                         -- 마지막 변경 시각
);

CREATE INDEX idx_user_noti_uuid ON user_notification_pref(uuid);
CREATE INDEX idx_user_noti_scope ON user_notification_pref USING GIN(noti_scope);
CREATE INDEX idx_user_noti_type ON user_notification_pref USING GIN(noti_type);
-- CREATE INDEX idx_user_noti_gmail ON user_notification_pref(gmail);  -- 필요 시 전송자 추적용

CREATE TABLE user_noti_stat (
  id SERIAL PRIMARY KEY,

  uuid UUID NOT NULL REFERENCES user_info(uuid) ON DELETE CASCADE,
  -- 사용자 식별자 (통합 기준)

  channel TEXT NOT NULL,                        -- 알림 채널: gmail / slack / kakao / app_push 등
  sent_count INT DEFAULT 0,                     -- 전송된 알림 수
  clicked_count INT DEFAULT 0,                  -- 클릭된 알림 수

  last_sent_at TIMESTAMP,                       -- 최근 알림 전송 시각
  last_clicked_at TIMESTAMP,                    -- 최근 알림 클릭 시각

  updated_at TIMESTAMP                          -- 마지막 통계 갱신 시각
);

CREATE UNIQUE INDEX idx_user_noti_stat_user_channel ON user_noti_stat(uuid, channel);

CREATE TABLE user_device_profile (
  uuid UUID PRIMARY KEY REFERENCES user_info(uuid) ON DELETE CASCADE,
  -- 🧾 1인 유저 기준, 여러 디바이스 등록 정보 통합 저장

  device_id TEXT[] DEFAULT ARRAY[]::TEXT[],
  -- ✅ 디바이스 식별자 배열 (예: ['abc123', 'def456']) → 빠른 포함 여부 검색용
  -- → 디바이스마다 고유 fingerprint or UUID

  devices JSONB DEFAULT '[]'::JSONB,
  -- ✅ 디바이스 정보 상세 묶음
  -- 예시:
  -- [
  --   {
  --     "device_id": "abc123",
  --     "name": "My MacBook",
  --     "type": "desktop",
  --     "os": "macOS"
  --   },
  --   {
  --     "device_id": "def456",
  --     "name": "Galaxy S23",
  --     "type": "mobile",
  --     "os": "Android"
  --   }
  -- ]

  -- 🖥 현재 접속 상태
  current_browser TEXT,
  -- 예: 'Chrome', 'Safari'

  current_user_agent TEXT,
  -- 예: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 13_4_1) AppleWebKit/...'

  current_ip_address TEXT,
  -- 예: '123.45.67.89'

  current_location TEXT,
  -- 예: 'Seoul, KR' (GeoIP 기반 위치 정보)

  -- 🔐 보안 상태
  is_trusted BOOLEAN DEFAULT FALSE,
  -- 사용자가 명시적으로 '신뢰한 기기'로 지정했는지 여부

  is_blocked BOOLEAN DEFAULT FALSE,
  -- 보안 위협 또는 관리자 판단으로 차단된 상태

  -- 🕒 기록
  registered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  last_used_at TIMESTAMP,
  updated_at TIMESTAMP
);
-- 빠른 디바이스 포함 여부 탐색 (특정 디바이스 사용자인지)
CREATE INDEX idx_user_device_ids ON user_device_profile USING GIN(device_id);

-- 현재 접속 지역 또는 IP 기반 필터링
CREATE INDEX idx_user_device_current_ip ON user_device_profile(current_ip_address);
CREATE INDEX idx_user_device_location ON user_device_profile(current_location);

-- 보안 제어용 인덱스
CREATE INDEX idx_user_device_security_flags ON user_device_profile(is_trusted, is_blocked);

CREATE TABLE user_secret (
  uuid UUID PRIMARY KEY REFERENCES user_info(uuid) ON DELETE CASCADE,
  -- 유저 통합 식별자 기준 1:1 민감 정보 저장소

  -- 🔐 비밀번호 인증 정보
  password_hash TEXT,                                  -- 단방향 해시 (bcrypt, argon2 등)
  password_salt TEXT,                                  -- (선택) 솔트값 (PBKDF2 등 대응 시)
  password_algo TEXT DEFAULT 'bcrypt',                 -- 사용 해시 알고리즘 기록용

  -- 🔑 외부 LLM/서비스 API 키 저장소 (우리가 대신 관리하는 키 포함 가능)
  api_keys JSONB DEFAULT '{}'::JSONB,
  -- 예시:
  -- {
  --   "openai": "sk-abc...",
  --   "fireworks": "fk-xyz...",
  --   "slack": "xoxb-xxx...",
  --   "notion": "secret_xxx..."
  -- }

  -- 🔍 API 키 메타데이터 저장소 (보안 분석/키 관리용)
  api_keys_meta JSONB DEFAULT '{}'::JSONB,
  -- 예시:
  -- {
  --   "openai": {
  --     "created_at": "2024-12-01T00:00:00Z",
  --     "expires_at": "2025-12-01T00:00:00Z",
  --     "scopes": ["chat", "embedding"]
  --   },
  --   "fireworks": {
  --     "note": "업무용 키, 관리자 전용"
  --   }
  -- }

  -- 🔄 OAuth 연동 토큰 저장소 (개인 계정 연동 등)
  oauth_tokens JSONB DEFAULT '{}'::JSONB,
  -- 예시:
  -- {
  --   "google": {
  --     "access_token": "ya29...",
  --     "refresh_token": "1//...",
  --     "expires_at": "2024-12-01T23:59:59Z"
  --   },
  --   "github": {
  --     "access_token": "...",
  --     "scope": "repo,read:user"
  --   }
  -- }

  -- 🚫 보안 잠금 정보
  login_fail_count INT DEFAULT 0,                      -- 연속 로그인 실패 횟수
  last_failed_login TIMESTAMP,                         -- 마지막 실패 시각
  account_locked_until TIMESTAMP,                      -- 일정 시간 잠금 시각

  -- 🕒 기록
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP
);

CREATE TABLE llm_api_key_pool (
  id SERIAL PRIMARY KEY,

  -- 🔑 키 구분 정보
  provider TEXT NOT NULL,                        -- 예: 'fireworks', 'openrouter', 'openai'
  api_key TEXT NOT NULL,                         -- 실제 API Key (앱단 암호화 저장 권장)
  model TEXT NOT NULL,                           -- 예: 'gpt-4o', 'claude-sonnet', 'mixtral'

  -- 📛 태깅 및 그룹 지정
  label TEXT,                                    -- 내부 식별자 (예: 'fw_main_01')
  user_group TEXT,                               -- 특정 유저 그룹 지정 (예: 'internal_testers')

  -- ✅ 상태 및 사용 제어
  is_active BOOLEAN DEFAULT TRUE,                -- 사용 가능 여부
  is_fallback BOOLEAN DEFAULT FALSE,             -- fallback 후보 여부 (장애 시 대체)
  is_test_only BOOLEAN DEFAULT FALSE,            -- 테스트 전용 키 여부

  -- 📊 사용량 추적
  usage_daily INT DEFAULT 0,                     -- 일일 호출 수 (매일 리셋 예정)
  usage_total BIGINT DEFAULT 0,                  -- 전체 누적 호출 수

  daily_quota INT DEFAULT 10000,                 -- 일일 호출 한도 (초과 시 자동 차단 또는 fallback 전환)
  auto_reset_policy TEXT DEFAULT 'daily',        -- 사용량 리셋 정책: 'daily' / 'weekly' / 'manual'
  reset_at TIMESTAMP,                            -- 다음 리셋 예정 시각 (스케줄링 기준 시점)

  -- 🕒 운영 로그
  last_used_at TIMESTAMP,                        -- 마지막 호출 시각
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP
);

-- 🔍 인덱스 구성 (상태 탐색 + 그룹 분기 + 모델 분리)
CREATE INDEX idx_llm_key_provider ON llm_api_key_pool(provider);
CREATE INDEX idx_llm_key_status ON llm_api_key_pool(is_active, is_fallback);
CREATE INDEX idx_llm_key_model ON llm_api_key_pool(model);
CREATE INDEX idx_llm_key_group ON llm_api_key_pool(user_group);

CREATE TABLE llm_request_log (
  id BIGSERIAL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,  -- ✅ 여기 한 번만 선언

  -- 🔐 호출 주체 및 키 추적
  uuid UUID NOT NULL REFERENCES user_info(uuid) ON DELETE SET NULL,
  key_id INT REFERENCES llm_api_key_pool(id) ON DELETE SET NULL,

  -- 🏷️ 호출 기능 분류
  tag TEXT,
  stage TEXT,

  -- 🤖 모델 및 파라미터 정보
  provider TEXT NOT NULL,
  model TEXT NOT NULL,
  params JSONB,

  -- 📊 비용 및 토큰 추적
  tokens INT[] CHECK (array_length(tokens, 1) = 3),
  cost_per_million NUMERIC[] CHECK (array_length(cost_per_million, 1) = 2),
  cost_usd NUMERIC(10,5),

  -- 📥 프롬프트 및 응답
  prompt TEXT,
  completion TEXT,

  -- ⚠️ 결과 상태
  success BOOLEAN,
  error_message TEXT,

  -- ⏱️ 시간 정보
  duration_ms INT,
  user_latency_ms INT,

  PRIMARY KEY (id, created_at)
)
PARTITION BY RANGE (created_at);

-- 인덱스
CREATE INDEX idx_llm_log_user_date ON llm_request_log(uuid, created_at DESC);
CREATE INDEX idx_llm_log_model ON llm_request_log(model);
CREATE INDEX idx_llm_log_success ON llm_request_log(success);
CREATE TABLE llm_request_log_202405 PARTITION OF llm_request_log
FOR VALUES FROM ('2024-05-01') TO ('2024-06-01');
-- 먼저 트리거 함수 정의

CREATE VIEW v_llm_daily_usage AS
SELECT
  model,
  DATE(created_at) AS log_date,
  COUNT(*) AS calls,
  SUM(cost_usd) AS total_cost,
  AVG(duration_ms) AS avg_response_time
FROM llm_request_log
GROUP BY model, DATE(created_at);

CREATE TABLE user_plan (
  -- 🆔 유저 식별
  uuid UUID PRIMARY KEY REFERENCES user_info(uuid) ON DELETE CASCADE,
  -- 유저 식별자와 1:1 매핑 (삭제 시 연쇄 삭제)

  -- 🧾 요금제 구분
  plan_key TEXT DEFAULT 'free',                          -- 시스템 내부 키 (예: 'free', 'basic', 'premium')
  plan_label TEXT,                                       -- UI 표시용 요금제명 (예: 'Pro AI+', 'Team Ultimate')

  -- 📊 사용량 제한
  max_commits_per_day INT,                               -- 일별 커밋 생성 최대 횟수
  max_commits_per_month INT,                             -- 월별 커밋 생성 제한
  max_describes_per_month INT,                           -- 월별 commit-describe 호출 가능 횟수
  max_uploads_per_day INT,                               -- 일일 커밋 메시지 업로드 가능 횟수 (ex: LLM 호출용 입력 업로드)

  -- 💬 알림/연동 채널 권한
  kakao_noti_remaining INT DEFAULT 0,                    -- 카카오 알림 남은 횟수
  slack_enabled BOOLEAN DEFAULT FALSE,                   -- 슬랙 연동 가능 여부

  -- 📺 UX 및 광고
  ad_layer_enabled BOOLEAN DEFAULT TRUE,                 -- 광고 레이어 노출 여부 (무료 플랜에서 주로 사용)
  instant_commit_generation BOOLEAN DEFAULT FALSE,       -- 클릭 없이 자동 커밋 메시지 생성 UX 허용 여부

  -- 💾 데이터 저장 / 리포트 기능
  save_commit_message BOOLEAN DEFAULT TRUE,              -- 커밋 메시지 저장 가능 여부
  save_describe_enabled BOOLEAN DEFAULT TRUE,            -- describe 결과 저장 허용 여부
  commit_report_enabled BOOLEAN DEFAULT FALSE,           -- 커밋 리포트 사용 여부 (서사 요약)
  visualization_report_enabled BOOLEAN DEFAULT FALSE,    -- 커밋 시각화 리포트 (flow-chart 등)

  -- 🧠 커밋 프롬프트 개인화
  prompt_personalization_enabled BOOLEAN DEFAULT FALSE,  -- 사용자 커밋 스타일 반영 여부 (LLM fine-tune류)

  -- 🔒 데이터 보존 정책
  data_retention_days INT DEFAULT 30,                    -- 메시지/히스토리 보존 기간 (일 단위)

  -- 👥 팀 협업 기능
  team_features_enabled BOOLEAN DEFAULT FALSE,           -- 팀 협업/분석/역할 기능 사용 여부

  -- 💵 요금 정보
  monthly_price_usd NUMERIC(6,2),                        -- 월 요금 (USD)
  trial_days INT DEFAULT 0,                              -- 트라이얼 기간 (일)

  -- 🕒 상태 정보
  is_trial_active BOOLEAN DEFAULT FALSE,                 -- 현재 체험판 활성 여부
  started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,        -- 요금제 시작 시각
  expires_at TIMESTAMP,                                  -- 종료일 (갱신 필요 시점)
  updated_at TIMESTAMP                                   -- 최근 변경일
);
CREATE INDEX idx_user_plan_expiry ON user_plan(expires_at);
CREATE INDEX idx_user_plan_type ON user_plan(plan_key);


CREATE TABLE user_plan_history (
  id SERIAL PRIMARY KEY,

  -- 🆔 사용자 식별
  uuid UUID NOT NULL REFERENCES user_info(uuid) ON DELETE CASCADE,
  -- 요금제 변경 대상 사용자

  -- 🔁 변경 요금제 정보
  old_plan_key TEXT,                                -- 변경 전 plan_key (예: 'free')
  new_plan_key TEXT,                                -- 변경 후 plan_key (예: 'premium')
  old_plan_label TEXT,                              -- UI 표시용 이전 요금제 라벨
  new_plan_label TEXT,                              -- UI 표시용 신규 요금제 라벨

  -- 💳 과금 및 조건 변화
  old_price_usd NUMERIC(6,2),                       -- 이전 요금제 가격
  new_price_usd NUMERIC(6,2),                       -- 변경 후 요금제 가격
  was_trial BOOLEAN DEFAULT FALSE,                  -- 트라이얼 종료 후 전환 여부

  -- 📅 적용 기간 및 종료일 (단기 플랜/취소용)
  effective_from TIMESTAMP,                         -- 새 요금제가 실제로 적용된 시점
  effective_until TIMESTAMP,                        -- 이 요금제 적용 종료 시점 (예: 중간 취소, 만료 등)

  -- 🔧 변경 메타 정보
  changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,   -- 실제 변경 기록 시각 (정확한 트리거 타임)
  changed_by TEXT,                                  -- 변경 주체: 'user' / 'admin' / 'system'
  source TEXT,                                      -- 변경 유입 경로: 'promotion', 'referral', 'event', 'billing_fail'
  note TEXT,                                        -- 설명 또는 관리자 메모

  -- 📊 분석 메타
  commit_usage_snapshot INT,                        -- 변경 당시 커밋 누적 수
  describe_usage_snapshot INT,                      -- 변경 당시 describe 누적 수
  kakao_noti_remaining_snapshot INT,                -- 알림 잔여 수
  is_team_plan BOOLEAN DEFAULT FALSE                -- 팀 요금제 여부 플래그
);
CREATE INDEX idx_plan_history_user_time ON user_plan_history(uuid, changed_at DESC);
CREATE INDEX idx_plan_history_trial_filter ON user_plan_history(was_trial, is_team_plan);

CREATE TABLE user_reward_log (
  id BIGSERIAL PRIMARY KEY,  -- 보상 로그 고유 ID (대량 이벤트 대응 위해 BIGSERIAL 사용)

  -- 🎯 보상 수신자
  receiver_uuid UUID NOT NULL REFERENCES user_info(uuid) ON DELETE CASCADE,
  -- 리워드 받는 사용자 (ex: 알림 획득, 광고 제거 혜택 등)

  -- 🔄 트리거 정보
  trigger_type TEXT NOT NULL,
  -- 보상 트리거 유형 (예: 'referral_signup', 'referral_5combo', 'promo_join', 'plan_upgrade', 'daily_mission')

  -- 🎁 보상 정보
  reward_type TEXT NOT NULL,
  -- 보상 내용 유형 (예: 'kakao_noti', 'ad_free_24h', 'slack_unlocked', 'commit_report')

  reward_value INT,
  -- 수치형 보상량 (예: 10 → 알림 10건, 1 → 리포트 1회)

  reward_unit TEXT,
  -- 단위 (예: 'count', 'hour', 'day', 'once')

  -- 🔗 연관 유저/이벤트
  source_uuid UUID,
  -- 트리거 제공자 (예: 추천인 UUID, 팀장 등)

  related_event TEXT,
  -- 연관 이벤트 ID, 쿠폰 코드, 캠페인 이름 등 (예: 'ref_ABC123', 'launch_promo_2025')

  -- 📆 상태 및 유효기간
  reward_status TEXT DEFAULT 'active',
  -- 보상 상태: 'active' / 'used' / 'expired' / 'revoked'

  reward_expire_at TIMESTAMP,
  -- 보상 만료일 (예: 2025-06-01까지 사용 가능)

  -- 🗒️ 메모 및 기록
  memo TEXT,
  -- 내부 운영 기록 / 메모 (예: "5명 누적 추천 달성 보상 지급")

  -- 🕒 시각 정보
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  used_at TIMESTAMP,               -- 보상 사용 처리 시각 (null이면 미사용)
  updated_at TIMESTAMP            -- 상태/만료 등 변경 시 갱신
);

CREATE INDEX idx_reward_receiver_status ON user_reward_log(receiver_uuid, reward_status);
CREATE INDEX idx_reward_expiry ON user_reward_log(reward_expire_at);
CREATE INDEX idx_reward_trigger_event ON user_reward_log(trigger_type, related_event);

CREATE TABLE user_feedback_log (
  id SERIAL PRIMARY KEY,
  uuid UUID REFERENCES user_info(uuid) ON DELETE CASCADE,

  feedback_type TEXT,              -- 예: 'onboarding', 'feature_request', 'bug'
  content TEXT,                    -- 유저가 남긴 내용
  page_context TEXT,              -- 어느 페이지에서 제출됐는지 (예: 'commit_flow', 'vs_extension')

  score INT,                      -- 만족도 (1~5 등급 등)
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE user_action_log (
  id BIGSERIAL PRIMARY KEY,
  uuid UUID REFERENCES user_info(uuid) ON DELETE CASCADE,

  action TEXT NOT NULL,            -- 예: 'open_editor', 'generate_commit', 'click_upgrade'
  context TEXT,                    -- 기능/화면/요소 ID (예: 'vscode_popup', 'main/commit')
  metadata JSONB,                 -- 부가 정보 (버튼 위치, 커밋 길이 등)

  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE user_deletion_request (
  uuid UUID PRIMARY KEY REFERENCES user_info(uuid) ON DELETE CASCADE,

  reason TEXT,                    -- 탈퇴 사유
  feedback TEXT,                 -- 자유 응답
  status TEXT DEFAULT 'pending', -- 'pending' / 'completed' / 'rejected'
  requested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  completed_at TIMESTAMP
);
-- 공통 updated_at 갱신 함수
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE UNIQUE INDEX idx_user_email ON user_info(email);
CREATE UNIQUE INDEX idx_user_uuid ON user_info(uuid);
CREATE INDEX idx_user_phone ON user_info(phone);

CREATE TRIGGER set_updated_at_user_info
BEFORE UPDATE ON user_info
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE OR REPLACE FUNCTION deactivate_inactive_users()
RETURNS VOID AS $$
BEGIN
  UPDATE user_info SET is_active = FALSE
  WHERE last_active_date < NOW() - INTERVAL '1 year'
    AND is_active = TRUE;
END;
$$ LANGUAGE plpgsql;
CREATE UNIQUE INDEX idx_oauth_google_id ON user_oauth(google_id) WHERE google_id IS NOT NULL;
CREATE UNIQUE INDEX idx_oauth_kakao_id ON user_oauth(kakao_id) WHERE kakao_id IS NOT NULL;
CREATE UNIQUE INDEX idx_oauth_github_id ON user_oauth(github_id) WHERE github_id IS NOT NULL;
-- 세션 만료 정리용 함수
CREATE OR REPLACE FUNCTION delete_expired_sessions()
RETURNS VOID AS $$
BEGIN
  DELETE FROM user_session WHERE expires_at < NOW();
END;
$$ LANGUAGE plpgsql;

-- 세션 만료 시간 인덱스
CREATE INDEX idx_user_session_expires_at ON user_session(expires_at);
CREATE INDEX idx_user_noti_channels ON user_notification_pref USING GIN(noti_type);
DROP TABLE IF EXISTS user_noti_stat CASCADE;

CREATE TABLE user_noti_stat (
  id SERIAL,
  uuid UUID NOT NULL REFERENCES user_info(uuid) ON DELETE CASCADE,
  channel TEXT NOT NULL,
  sent_count INT DEFAULT 0,
  clicked_count INT DEFAULT 0,
  last_sent_at TIMESTAMP,
  last_clicked_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP,
  PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

CREATE INDEX idx_device_ids ON user_device_profile USING GIN(device_id);
CREATE OR REPLACE FUNCTION check_key_usage_limit()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.usage_daily > NEW.daily_quota THEN
    NEW.is_active := FALSE;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_key_usage
BEFORE UPDATE ON llm_api_key_pool
FOR EACH ROW EXECUTE FUNCTION check_key_usage_limit();

-- 먼저 트리거 함수 정의
CREATE OR REPLACE FUNCTION insert_plan_history()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO user_plan_history (
    uuid, old_plan_key, new_plan_key,
    old_plan_label, new_plan_label,
    old_price_usd, new_price_usd,
    was_trial, changed_by, source
  )
  VALUES (
    OLD.uuid, OLD.plan_key, NEW.plan_key,
    OLD.plan_label, NEW.plan_label,
    OLD.monthly_price_usd, NEW.monthly_price_usd,
    OLD.is_trial_active, 'system', 'plan_change'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 트리거 등록
CREATE TRIGGER log_plan_change
AFTER UPDATE OF plan_key ON user_plan
FOR EACH ROW
WHEN (OLD.plan_key IS DISTINCT FROM NEW.plan_key)
EXECUTE FUNCTION insert_plan_history();
CREATE OR REPLACE FUNCTION expire_rewards()
RETURNS VOID AS $$
BEGIN
  UPDATE user_reward_log
  SET reward_status = 'expired'
  WHERE reward_status = 'active'
    AND reward_expire_at < NOW();
END;
$$ LANGUAGE plpgsql;
CREATE TABLE audit_log (
  id BIGSERIAL PRIMARY KEY,
  table_name TEXT,
  operation TEXT, -- 'INSERT', 'UPDATE', 'DELETE'
  record_id TEXT,
  changed_by TEXT,
  changes JSONB,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 여기는 Repo 관련 테이블 완성 이후에 가능
-- CREATE TABLE commit_message_info (
--   id BIGSERIAL PRIMARY KEY,

--   -- 🔗 유저 및 레포 식별 정보
--   uuid UUID REFERENCES user_info(uuid) ON DELETE CASCADE,
--   repo_id INT REFERENCES repo_meta(repo_id) ON DELETE SET NULL,  -- 레포 정보 연결
--   commit_hash TEXT,                         -- 실제 Git 커밋 해시 (적용 후 기록용)

--   -- 📄 커밋 메시지 생성 대상 및 컨텍스트
--   file_path TEXT NOT NULL,                 -- 어떤 파일에 대한 메시지인지
--   diff_summary TEXT,                       -- diff 요약 (처음~끝)
--   func_summary TEXT,                       -- 함수 요약 (def, call graph 등)
--   readme_summary TEXT,                     -- 레포 or 폴더의 요약 정보

--   -- 🤖 LLM 처리 정보
--   model_used TEXT,                         -- llama4-scout 등 모델명
--   tag TEXT,                                -- mk_msg_out, explain_in 등 기능 태그
--   status TEXT DEFAULT 'pending',          -- 'pending' / 'approved' / 'committed'
--   editable BOOLEAN DEFAULT TRUE,          -- Slack/웹에서 편집 가능 여부

--   -- ✍️ 최종 커밋 메시지
--   commit_msg TEXT,                         -- 생성된 커밋 메시지

--   -- 🕒 메타
--   created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
--   updated_at TIMESTAMP
-- );

-- CREATE TABLE commit_review_log (
--   id BIGSERIAL PRIMARY KEY,

--   -- 🔗 참조 정보
--   commit_id BIGINT REFERENCES commit_message_info(id) ON DELETE CASCADE,
--   clicked_by UUID REFERENCES user_info(uuid) ON DELETE SET NULL,   -- 유저 삭제 시 보존

--   -- 🕒 클릭/검토 시점 정보
--   clicked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
--   client_ip TEXT,
--   user_agent TEXT,

--   -- ✍️ 메시지 검토 및 확정 정보
--   final_msg TEXT,                         -- 최종 확정 커밋 메시지 (수정 가능)
--   approved BOOLEAN DEFAULT FALSE,         -- 수동 승인 여부
--   edited BOOLEAN DEFAULT FALSE            -- 클릭 후 메시지 직접 수정 여부 (검증/통계용)
-- );