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
  -- user_uuid UUID NOT NULL REFERENCES user_info(uuid) ON DELETE CASCADE, -- 변경된 부분
  user_uuid UUID NOT NULL, -- FK 제약은 아래 ALTER TABLE로 추가하거나, 테이블 생성 시점에 user_info가 있다면 직접 추가
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

-- user_info 테이블이 먼저 생성되었다고 가정하고 FK 추가 (또는 테이블 생성문에 직접 포함)
ALTER TABLE user_session
ADD CONSTRAINT fk_user_session_user_uuid
FOREIGN KEY (user_uuid) REFERENCES user_info(uuid) ON DELETE CASCADE;

-- 필수 인덱스 (user_uuid로 변경)
CREATE INDEX idx_user_session_user_uuid ON user_session(user_uuid);
CREATE INDEX idx_user_session_last_seen ON user_session(last_seen DESC);
CREATE INDEX idx_user_session_expires_at ON user_session(expires_at);
-- session_id는 UNIQUE 제약으로 자동 인덱싱

-- updated_at 자동 갱신 트리거 (user_info의 set_updated_at() 함수 재활용)
CREATE TRIGGER set_updated_at_user_session
BEFORE UPDATE ON user_session
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 세션 만료 정리용 함수 (주기적 실행 필요)
CREATE OR REPLACE FUNCTION delete_expired_sessions()
RETURNS VOID AS $$
BEGIN
 DELETE FROM user_session WHERE expires_at < NOW();
END;
$$ LANGUAGE plpgsql;
CREATE TABLE user_notification_pref (
 -- 🆔 식별자
 id SERIAL PRIMARY KEY,
 uuid UUID NOT NULL REFERENCES user_info(uuid) ON DELETE CASCADE,

 -- 📌 알림 범위 및 유형 설정 (JSONB로 통합, 컬럼명 변경)
  alert_configurations JSONB DEFAULT '{}'::JSONB,
  -- 예시: '{"personal": ["commit_yn", "generic_link"], "team": ["upload_yn"]}'

 -- 📢 알림 채널 활성화 여부 (실제 주소/토큰은 user_secret 참조)
  enable_gmail_noti BOOLEAN DEFAULT TRUE,   -- Gmail 알림은 기본 활성화, 사용자가 끌 수 있음
  enable_slack_noti BOOLEAN DEFAULT FALSE,
  enable_kakao_noti BOOLEAN DEFAULT FALSE,
  enable_discord_noti BOOLEAN DEFAULT FALSE,
  enable_telegram_noti BOOLEAN DEFAULT FALSE,
  enable_app_push_noti BOOLEAN DEFAULT FALSE,

 -- 🔄 자동 트리거 (작업/알림 시작 조건)
 task_trigger TEXT DEFAULT 'vscode_start',
 noti_trigger TEXT DEFAULT 'vscode_close',

 -- 🔕 조용한 시간 설정 (해당 시간대엔 알림 비활성화)
 quiet_time_start TIME,
 quiet_time_end TIME,

 -- 🚫 전체 알림 차단 여부
 is_enabled BOOLEAN DEFAULT TRUE,

 -- 🕒 기록
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 updated_at TIMESTAMP
);

-- 인덱스 (컬럼명 변경에 따라 인덱스명도 수정 제안)
CREATE INDEX idx_user_alert_config_uuid ON user_notification_pref(uuid);
CREATE INDEX idx_user_alert_config_gin ON user_notification_pref USING GIN(alert_configurations);

-- updated_at 자동 갱신 트리거 (set_updated_at() 함수 재활용)
CREATE TRIGGER set_updated_at_user_notification_pref
BEFORE UPDATE ON user_notification_pref
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TABLE user_noti_stat (
  uuid UUID PRIMARY KEY REFERENCES user_info(uuid) ON DELETE CASCADE,
  channels_used TEXT[] DEFAULT ARRAY[]::TEXT[],
  sent_counts INTEGER[] DEFAULT ARRAY[]::INTEGER[],
  clicked_counts INTEGER[] DEFAULT ARRAY[]::INTEGER[],
  last_activity_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP
);

CREATE TRIGGER set_updated_at_user_noti_stat
BEFORE UPDATE ON user_noti_stat
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TABLE user_device_profile (
  uuid UUID PRIMARY KEY REFERENCES user_info(uuid) ON DELETE CASCADE,

  device_id TEXT[] DEFAULT ARRAY[]::TEXT[], -- 검색용 device_id 목록

  devices JSONB DEFAULT '[]'::JSONB,
  -- 예시:
  -- [
  --   {
  --     "device_id": "abc123", "name": "My MacBook", "type": "desktop", "os": "macOS",
  --     "session_count": 15, "is_trusted": true, "is_blocked": false,
  --     "first_seen_at": "YYYY-MM-DDTHH:MM:SSZ", "last_seen_at": "YYYY-MM-DDTHH:MM:SSZ"
  --   }
  -- ]

  -- current_* 컬럼들은 제거

  -- is_trusted, is_blocked 테이블 레벨 컬럼은 devices JSON 내부로 이동

  registered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, -- 이 사용자 프로파일 로우 생성 시점
  last_used_at TIMESTAMP, -- 이 사용자의 어떤 디바이스든 마지막 사용 시점 (user_session의 last_seen과 유사한 역할, 애플리케이션에서 업데이트 필요)
  updated_at TIMESTAMP
);

CREATE INDEX idx_user_device_profile_device_ids_gin ON user_device_profile USING GIN(device_id);
-- devices JSONB 내부 필드 검색을 위한 GIN 인덱스 (필요시)
-- CREATE INDEX idx_user_device_profile_devices_gin ON user_device_profile USING GIN(devices);
-- CREATE INDEX idx_user_device_profile_devices_trusted_gin ON user_device_profile USING GIN((devices -> 'is_trusted')); -- 특정 필드 대상 GIN

CREATE TRIGGER set_updated_at_user_device_profile
BEFORE UPDATE ON user_device_profile
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TABLE user_secret (
 uuid UUID PRIMARY KEY REFERENCES user_info(uuid) ON DELETE CASCADE,

 -- 🔐 비밀번호 관련 컬럼 삭제 (OAuth-only 정책)

 -- 🔑 외부 LLM/서비스 API 키 저장소 (앱 레벨 암호화 필수)
 api_keys JSONB DEFAULT '{}'::JSONB,
 -- 예시:
 -- {
 --   "openai": "encrypted_sk-abc...",
 --   "fireworks": "encrypted_fk-xyz...",
 --   "slack_user_token": "encrypted_xoxp-xxx..."
 -- }

 -- 🔍 API 키 메타데이터 저장소
 api_keys_meta JSONB DEFAULT '{}'::JSONB,
 -- 예시:
 -- {
 --   "openai": { "created_at": "...", "expires_at": "...", "scopes": [...] },
 --   "slack_user_token": { "note": "사용자 개인 Slack 연동용" }
 -- }

 -- 🔄 OAuth 연동 토큰 저장소 (앱 레벨 암호화 필수)
 -- 사용자를 대신하여 외부 서비스에 접근하기 위한 토큰
 oauth_tokens JSONB DEFAULT '{}'::JSONB,
 -- 예시:
 -- {
 --   "google": {
 --     "access_token": "encrypted_ya29...",
 --     "refresh_token": "encrypted_1//...",
 --     "expires_at": "YYYY-MM-DDTHH:MM:SSZ",
 --     "scopes": ["https://www.googleapis.com/auth/gmail.readonly"]
 --   },
 --   "github": {
 --     "access_token": "encrypted_gho_...",
 --     "refresh_token": "encrypted_ghr_...",
 --     "refresh_token_expires_in": ...,
 --     "scope": "repo,read:user"
 --   }
 -- }

 -- 🚫 보안 잠금 정보 (OAuth 실패 시에도 계정 잠금 로직이 필요할 수 있음 - Provider별 정책 확인)
 login_fail_count INT DEFAULT 0,
 last_failed_login TIMESTAMP,
 account_locked_until TIMESTAMP,

 -- 🕒 기록
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 updated_at TIMESTAMP
);

-- updated_at 자동 갱신 트리거 (set_updated_at() 함수 재활용)
CREATE TRIGGER set_updated_at_user_secret
BEFORE UPDATE ON user_secret
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TABLE llm_key_config (
  id SERIAL PRIMARY KEY,
  provider TEXT NOT NULL,                     -- 예: 'fireworks', 'openai'
  api_key TEXT NOT NULL,                      -- 실제 API Key (앱단 암호화 저장 필수)
  model_served TEXT NOT NULL,                 -- 이 키가 제공하는 대표 모델 또는 모델 그룹 (예: 'gpt-4-turbo', 'claude-3-opus', 'general-purpose')
  label TEXT UNIQUE,                          -- 내부 고유 식별자 (예: 'fw_main_01', UK로 키 중복 방지 가능)
  user_group TEXT DEFAULT 'default',          -- 할당 대상 사용자 그룹 (예: 'free_tier', 'premium_tier', 'internal')
  is_fallback_candidate BOOLEAN DEFAULT FALSE,-- 장애 시 대체 후보로 사용될 수 있는지
  is_test_only BOOLEAN DEFAULT FALSE,         -- 테스트 전용 키인지
  is_active_overall BOOLEAN DEFAULT TRUE,     -- 이 키가 시스템 전체적으로 사용 가능한지 (수동 비활성화 등)
  priority INT DEFAULT 0,                     -- 키 선택 시 우선순위 (0이 가장 높음, 라우팅 로직에 사용)
  
  -- Provider Rate Limit 관리용 정보 (애플리케이션에서 이 값을 참조하여 자체 Rate Limiting 구현)
  rpm_limit INT,                              -- 이 키의 분당 요청 수 한도 (Provider 정책 명시)
  tpm_limit INT,                              -- 이 키의 분당 토큰 수 한도 (Provider 정책 명시)
  
  last_used_at TIMESTAMP,                     -- 이 키가 마지막으로 성공적으로 사용된 시각 (키 회전용)
  
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP
);

-- 인덱스
CREATE INDEX idx_llm_key_config_provider ON llm_key_config(provider);
CREATE INDEX idx_llm_key_config_model_served ON llm_key_config(model_served);
CREATE INDEX idx_llm_key_config_user_group ON llm_key_config(user_group);
CREATE INDEX idx_llm_key_config_status_priority ON llm_key_config(is_active_overall, priority, last_used_at); -- 키 선택 로직 최적화용
CREATE INDEX idx_llm_key_config_last_used ON llm_key_config(last_used_at); -- 키 회전 로직 지원

-- api_key 자체의 중복을 막고 싶다면, (provider, 암호화된_api_key)에 UNIQUE 인덱스 고려
-- CREATE UNIQUE INDEX idx_llm_key_config_provider_apikey ON llm_key_config(provider, api_key);

-- updated_at 자동 갱신 트리거
CREATE TRIGGER set_updated_at_llm_key_config
BEFORE UPDATE ON llm_key_config
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TABLE llm_request_log (
 id BIGSERIAL,
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

 uuid UUID REFERENCES user_info(uuid) ON DELETE SET NULL,
 key_id INT REFERENCES llm_key_config(id) ON DELETE SET NULL,

 tag TEXT,
 stage TEXT,

 provider TEXT NOT NULL,
 model TEXT NOT NULL,
 params JSONB,

  -- tokens[1]=prompt, tokens[2]=completion, tokens[3]=total
 tokens INT[] CHECK (array_length(tokens, 1) = 3),
  -- cost_per_million[1]=input_cost, cost_per_million[2]=output_cost (per million tokens in USD)
 cost_per_million NUMERIC[] CHECK (array_length(cost_per_million, 1) = 2),
 cost_usd NUMERIC(10,5), -- Calculated in application: (tokens[1]/1e6*cost_per_million[1]) + (tokens[2]/1e6*cost_per_million[2])

  -- MVP: DB에 직접 저장. 장기적으로는 외부 저장소 ID 또는 링크 저장 고려.
  -- 보관 주기 (예: 90일) 이후 PII 마스킹 및 벡터화 후 별도 영구 보존.
 prompt TEXT,
 completion TEXT,

 success BOOLEAN,
 error_message TEXT,
  error_code TEXT,

 duration_ms INT,
 user_latency_ms INT,

 PRIMARY KEY (id, created_at)
)
PARTITION BY RANGE (created_at);

-- 예시 파티션 (월별)
-- CREATE TABLE llm_request_log_y2025m05 PARTITION OF llm_request_log
-- FOR VALUES FROM ('2025-05-01') TO ('2025-06-01');
-- CREATE TABLE llm_request_log_y2025m06 PARTITION OF llm_request_log
-- FOR VALUES FROM ('2025-06-01') TO ('2025-07-01');
-- (자동 파티션 생성/관리 로직 필요)

-- 인덱스
CREATE INDEX idx_llm_log_user_created ON llm_request_log(uuid, created_at DESC);
CREATE INDEX idx_llm_log_key_id_created ON llm_request_log(key_id, created_at DESC);
CREATE INDEX idx_llm_log_model_created ON llm_request_log(model, created_at DESC);
CREATE INDEX idx_llm_log_success_created ON llm_request_log(success, created_at DESC);
CREATE INDEX idx_llm_log_tag_created ON llm_request_log(tag, created_at DESC);
-- CREATE INDEX idx_llm_log_created_at ON llm_request_log(created_at DESC); -- 파티션 키에 대한 단독 인덱스는 보통 불필요
-- ENUM 타입 정의 (user_plan 테이블 생성 전에 실행, user_info의 user_account_type과 별개)
CREATE TYPE plan_key_enum AS ENUM ('free', 'basic', 'premium', 'team_basic', 'team_premium', 'enterprise'); -- 예시 값, 실제 플랜에 맞게 조정

CREATE TABLE user_plan (
  uuid UUID PRIMARY KEY REFERENCES user_info(uuid) ON DELETE CASCADE,
  plan_key plan_key_enum DEFAULT 'free', -- ENUM 타입 적용
  plan_label TEXT,

  max_commits_per_day INT,
  max_commits_per_month INT,
  max_describes_per_month INT,
  max_uploads_per_day INT,

  kakao_noti_remaining INT DEFAULT 0,
  slack_enabled BOOLEAN DEFAULT FALSE,

  ad_layer_enabled BOOLEAN DEFAULT TRUE,
  instant_commit_generation BOOLEAN DEFAULT FALSE,

  save_commit_message BOOLEAN DEFAULT TRUE,
  save_describe_enabled BOOLEAN DEFAULT TRUE,
  commit_report_enabled BOOLEAN DEFAULT FALSE,
  visualization_report_enabled BOOLEAN DEFAULT FALSE,

  prompt_personalization_enabled BOOLEAN DEFAULT FALSE,
  data_retention_days INT DEFAULT 30, -- llm_request_log 원문 보관 기간과 연동

  team_features_enabled BOOLEAN DEFAULT FALSE,

  monthly_price_usd NUMERIC(6,2),
  trial_days INT DEFAULT 0,

  is_trial_active BOOLEAN DEFAULT FALSE,
  started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  expires_at TIMESTAMP,
  updated_at TIMESTAMP
);

CREATE INDEX idx_user_plan_expiry ON user_plan(expires_at);
CREATE INDEX idx_user_plan_type ON user_plan(plan_key); -- ENUM 타입에도 인덱스 유효

-- updated_at 자동 갱신 트리거
CREATE TRIGGER set_updated_at_user_plan
BEFORE UPDATE ON user_plan
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 요금제 변경 시 히스토리 자동 기록 트리거 함수 (원본 DDL 참조)
CREATE OR REPLACE FUNCTION insert_user_plan_history()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO user_plan_history (
  uuid,
    old_plan_key, new_plan_key,
    old_plan_label, new_plan_label,
    old_price_usd, new_price_usd,
    was_trial,
    changed_by, -- 'user', 'admin', 'system' 등으로 애플리케이션에서 설정 필요
    source,     -- 변경 유입 경로
    effective_from,
    effective_until,
    note
    -- 필요한 경우 스냅샷 컬럼 추가
 )
 VALUES (
    OLD.uuid,
    OLD.plan_key::TEXT, NEW.plan_key::TEXT, -- ENUM을 TEXT로 캐스팅하여 저장 (history 테이블은 TEXT 유지 시)
    OLD.plan_label, NEW.plan_label,
    OLD.monthly_price_usd, NEW.monthly_price_usd,
    OLD.is_trial_active,
    'system', -- 기본값, 실제 변경 주체는 앱에서 설정
    'plan_change_trigger', -- 트리거로 인한 변경 명시
    OLD.expires_at, -- 이전 만료일 또는 변경 시점
    NEW.expires_at, -- 새 만료일
    'Plan key changed from ' || OLD.plan_key || ' to ' || NEW.plan_key
 );
 RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE user_plan_history (
 id SERIAL PRIMARY KEY,
 uuid UUID NOT NULL REFERENCES user_info(uuid) ON DELETE CASCADE,

 old_plan_key TEXT, -- ENUM이었던 user_plan.plan_key의 과거 값을 TEXT로 저장 (유연성)
 new_plan_key TEXT, -- ENUM인 user_plan.plan_key의 현재 값을 TEXT로 저장
 old_plan_label TEXT,
 new_plan_label TEXT,

 old_price_usd NUMERIC(6,2),
 new_price_usd NUMERIC(6,2),
 was_trial BOOLEAN DEFAULT FALSE,

 effective_from TIMESTAMP, -- 새 요금제 적용 시작 시점 (user_plan.started_at과 유사할 수 있음)
 effective_until TIMESTAMP, -- 이 히스토리 레코드의 유효 종료 시점 (user_plan.expires_at과 유사할 수 있음)

 changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, -- 이 히스토리 레코드가 생성된 시점
 changed_by TEXT, -- 'user', 'admin', 'system', 'trigger' 등
 source TEXT,     -- 'promotion', 'referral', 'billing_fail', 'plan_change_trigger' 등
 note TEXT,

 -- 분석용 스냅샷 컬럼 (실제 구현 시 데이터 소스 및 필요성 재검토)
 commit_usage_snapshot INT,
 describe_usage_snapshot INT,
 kakao_noti_remaining_snapshot INT,
 is_team_plan BOOLEAN DEFAULT FALSE -- 변경 시점의 '새' 요금제가 팀 요금제였는지 여부

  -- updated_at 불필요 (INSERT 위주)
);

CREATE INDEX idx_plan_history_user_time ON user_plan_history(uuid, changed_at DESC);
CREATE INDEX idx_plan_history_trial_filter ON user_plan_history(was_trial, is_team_plan);
CREATE INDEX idx_plan_history_changed_by ON user_plan_history(changed_by);
CREATE INDEX idx_plan_history_new_plan_key ON user_plan_history(new_plan_key);
-- ENUM 타입 정의 (user_reward_log 테이블 생성 전에 실행)
CREATE TYPE reward_status_enum AS ENUM ('active', 'used', 'expired', 'revoked');

CREATE TABLE user_reward_log (
 id BIGSERIAL PRIMARY KEY,
 receiver_uuid UUID NOT NULL REFERENCES user_info(uuid) ON DELETE CASCADE,
 trigger_type TEXT NOT NULL,
 reward_type TEXT NOT NULL,
 reward_value NUMERIC, -- 시간 단위 등 소수점 보상 가능
 reward_unit TEXT,    -- 예: 'count', 'hour', 'day', 'once', 'percent'
 source_uuid UUID REFERENCES user_info(uuid) ON DELETE SET NULL, -- 추천인 등, FK 제약 추가
 related_event_id TEXT, -- 컬럼명 변경 반영
 reward_status reward_status_enum DEFAULT 'active', -- ENUM 타입 적용
 reward_expire_at TIMESTAMP,
 memo TEXT,
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 used_at TIMESTAMP,
 updated_at TIMESTAMP
);

CREATE INDEX idx_reward_receiver_status ON user_reward_log(receiver_uuid, reward_status);
CREATE INDEX idx_reward_expiry ON user_reward_log(reward_expire_at);
CREATE INDEX idx_reward_trigger_event ON user_reward_log(trigger_type, related_event_id);
CREATE INDEX idx_reward_source_uuid ON user_reward_log(source_uuid);

-- 만료된 보상 상태 자동 업데이트 함수 (주기적 실행 필요)
CREATE OR REPLACE FUNCTION expire_rewards()
RETURNS VOID AS $$
BEGIN
 UPDATE user_reward_log
 SET reward_status = 'expired'::reward_status_enum -- ENUM 타입으로 캐스팅
 WHERE reward_status = 'active'::reward_status_enum
  AND reward_expire_at IS NOT NULL -- 만료일이 설정된 경우에만
  AND reward_expire_at < NOW();
END;
$$ LANGUAGE plpgsql;

-- updated_at 자동 갱신 트리거
CREATE TRIGGER set_updated_at_user_reward_log
BEFORE UPDATE ON user_reward_log
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TABLE user_feedback_log (
 id SERIAL PRIMARY KEY,
 uuid UUID REFERENCES user_info(uuid) ON DELETE SET NULL, -- 피드백 남긴 사용자 (탈퇴 시 피드백은 익명으로 남김)

 feedback_type TEXT, -- MVP: TEXT 유지, 향후 ENUM 고려
 content TEXT NOT NULL,
 page_context TEXT,

 score INT, -- 만족도 (1~5 또는 1~10 등급 등, 선택적)
  contact_email TEXT, -- 추가 연락용 이메일 (선택적)
  is_resolved BOOLEAN DEFAULT FALSE, -- 피드백 처리 완료 여부
  resolved_at TIMESTAMP,          -- 처리 완료 시각
  resolver_note TEXT,             -- 처리자 메모

 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 updated_at TIMESTAMP -- 관리자 상태 변경 시 업데이트
);

CREATE INDEX idx_feedback_uuid ON user_feedback_log(uuid);
CREATE INDEX idx_feedback_type ON user_feedback_log(feedback_type);
CREATE INDEX idx_feedback_created_at ON user_feedback_log(created_at DESC);
CREATE INDEX idx_feedback_is_resolved ON user_feedback_log(is_resolved);

-- updated_at 자동 갱신 트리거
CREATE TRIGGER set_updated_at_user_feedback_log
BEFORE UPDATE ON user_feedback_log
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TABLE user_action_log (
 id BIGSERIAL, -- PK는 (id, created_at) 복합키로 변경
 uuid UUID REFERENCES user_info(uuid) ON DELETE SET NULL, -- 사용자 탈퇴 시 로그 익명화 후 보존
 action TEXT NOT NULL,
 context TEXT,
 metadata JSONB,
  -- 예시 metadata:
  -- 로그인 성공: {"method": "google_oauth"}
  -- 페이지 뷰: {"page_url": "/dashboard", "referrer": "...", "duration_on_page_ms": 15000}
  -- 커밋 생성 버튼 클릭: {"button_id": "generate_commit_main", "source_location": "vscode_extension_sidebar"}
  -- LLM 요청 (llm_request_log와 별개로 UI/UX 상의 액션): {"llm_action_tag": "commit_message_draft", "model_requested": "gpt-4o"}
  -- 설정 변경: {"setting_changed": "theme", "old_value": "dark", "new_value": "light"}
  -- 파일 업로드 시도: {"file_count": 3, "total_size_kb": 1024, "rejected_files": ["large_video.mp4"]}
  -- 검색 실행: {"search_term": "fix login bug", "result_count": 5}
  -- 기능 사용 빈도: {"feature_name": "code_analysis_v1", "parameters": {"depth": "full"}}
  -- 오류 발생 (UI/사용자 레벨): {"error_type": "validation_error", "field": "email", "message": "Invalid email format"}

 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, -- 액션 발생 시각, 파티션 키

  PRIMARY KEY (id, created_at) -- 파티션 테이블의 PK는 파티션 키를 포함
)
PARTITION BY RANGE (created_at); -- 파티션 기준: 1주일 또는 1일 (초기 1주일, 추후 1일로 변경 가능)

-- 예시 파티션 (실제 운영 시에는 자동 생성 로직 필요)
-- 주 단위 파티션 예시 (YYYY_WW 형식)
-- CREATE TABLE user_action_log_y2025w20 PARTITION OF user_action_log
-- FOR VALUES FROM ('2025-05-12') TO ('2025-05-19');
-- CREATE TABLE user_action_log_y2025w21 PARTITION OF user_action_log
-- FOR VALUES FROM ('2025-05-19') TO ('2025-05-26');

-- 일 단위 파티션 예시 (YYYYMMDD 형식)
-- CREATE TABLE user_action_log_y2025m05d25 PARTITION OF user_action_log
-- FOR VALUES FROM ('2025-05-25') TO ('2025-05-26');

-- 인덱스
CREATE INDEX idx_action_log_uuid_created_at ON user_action_log(uuid, created_at DESC);
CREATE INDEX idx_action_log_action_created_at ON user_action_log(action, created_at DESC);
CREATE INDEX idx_action_log_context_created_at ON user_action_log(context, created_at DESC);
-- metadata 내 특정 필드 검색이 잦다면 JSONB GIN 인덱스 고려 가능 (예: metadata->>'button_id')
-- CREATE INDEX idx_action_log_metadata_gin ON user_action_log USING GIN(metadata);
-- ENUM 타입 정의 (user_deletion_request 테이블 생성 전에 실행)
CREATE TYPE deletion_request_status_enum AS ENUM ('pending', 'processing', 'completed', 'rejected', 'error');

CREATE TABLE user_deletion_request (
  -- id SERIAL PRIMARY KEY, -- PK 변경: request_id 또는 (uuid, requested_at) 등 고려
  request_id UUID PRIMARY KEY DEFAULT gen_random_uuid(), -- 각 요청별 고유 ID (여러 번 요청 가능하도록)
  user_uuid UUID NOT NULL REFERENCES user_info(uuid) ON DELETE SET NULL, -- 요청한 사용자 (탈퇴 후에도 기록은 남김)
  -- user_info가 삭제되어도 이 요청 기록은 남아야 하므로 ON DELETE SET NULL.
  -- 또는 user_info가 삭제되면 이 요청의 status를 'completed' (또는 'user_account_deleted')로 업데이트하는 로직 필요.

  reason TEXT, feedback TEXT,
  status deletion_request_status_enum DEFAULT 'pending', -- ENUM 타입 적용
  requested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  completed_at TIMESTAMP,
  processed_by TEXT,
  processing_log JSONB,
  updated_at TIMESTAMP -- 상태 변경 등 업데이트 시
);

-- 인덱스
CREATE INDEX idx_user_deletion_user_uuid ON user_deletion_request(user_uuid); -- 컬럼명 변경
CREATE INDEX idx_user_deletion_status ON user_deletion_request(status);
CREATE INDEX idx_user_deletion_requested_at ON user_deletion_request(requested_at DESC);

-- updated_at 자동 갱신 트리거
CREATE TRIGGER set_updated_at_user_deletion_request
BEFORE UPDATE ON user_deletion_request
FOR EACH ROW EXECUTE FUNCTION set_updated_at();