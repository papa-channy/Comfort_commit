-- =====================================================================================
-- 파일: 06_user_device_profile.sql
-- 모듈: 01_user_module (사용자 모듈)
-- 설명: 사용자가 등록한 디바이스들의 프로필 정보를 통합 관리합니다.
-- 대상 DB: PostgreSQL Primary RDB (사용자 설정 및 보안 데이터)
-- 파티셔닝: 없음 (사용자당 1개의 로우)
-- MVP 중점사항: 사용자별 단일 로우, JSONB를 사용한 유연한 디바이스 목록 및 상세 정보 관리, 필수 인덱스.
-- 스케일업 고려사항: RLS 적용, JSONB 내부 필드 검색 최적화 (GIN 인덱스), 디바이스 수가 매우 많아질 경우 정규화 재검토.
-- =====================================================================================

-- 사용자 디바이스 프로필 테이블
CREATE TABLE user_device_profile (
  id id PRIMARY KEY REFERENCES user_info(id) ON DELETE CASCADE,
  -- user_info 테이블의 id를 참조하며, 사용자 탈퇴 시 관련 디바이스 프로필도 함께 삭제됩니다.

  device_uuids_array TEXT[] DEFAULT ARRAY[]::TEXT[],
  -- ✅ 사용자가 등록한 모든 디바이스의 고유 uuid 목록 (배열).
  -- 이 배열은 devices_info JSONB 내의 device_uuid들과 일관성을 유지해야 하며, 특정 device_uuid의 등록 여부 빠른 검색에 사용됩니다 (GIN 인덱스).

  devices_info JSONB DEFAULT '[]'::JSONB,
  -- ✅ 각 디바이스의 상세 정보를 담는 JSON 객체 배열.
  -- 예시 내부 객체 구조:
  -- {
  --   "device_uuid": "client_generated_unique_uuid_abc123", -- (이 값은 device_uuids_array에도 포함됨), 클라이언트에서 생성 및 관리
  --   "device_name": "My MacBook Pro 16",               -- 사용자가 설정한 디바이스 별칭
  --   "device_type": "laptop",                          -- 디바이스 유형 (ENUM 고려: 'desktop', 'laptop', 'mobile', 'tablet', 'wearable', 'iot_device', 'unknown')
  --   "os_name": "macOS",                               -- 운영체제 이름
  --   "os_version": "14.1",                             -- 운영체제 버전
  --   "app_client_name": "ComfortCommit_VSCode_Extension",-- 접속한 클라이언트 애플리케이션 이름
  --   "app_client_version": "1.2.3",                    -- 클라이언트 애플리케이션 버전
  --   "session_count": 150,                             -- 이 디바이스에서의 누적 세션 수 (user_session 로그 기반으로 집계 가능)
  --   "is_trusted_device": true,                        -- 사용자가 명시적으로 신뢰한 기기인지 여부
  --   "is_blocked_device": false,                       -- 보안 위협 또는 관리자 판단으로 차단된 기기인지 여부
  --   "first_seen_at": "YYYY-MM-DDTHH:MM:SSZ",          -- 이 디바이스가 서비스에 처음 등록/감지된 시각
  --   "last_seen_at": "YYYY-MM-DDTHH:MM:SSZ",           -- 이 디바이스가 마지막으로 사용된 시각 (세션 정보 기반 업데이트)
  --   "last_seen_ip": "123.45.67.89",                   -- 마지막 접속 IP
  --   "additional_details_json": {                      -- 기타 확장 정보 (JSON 객체)
  --     "screen_resolution": "1920x1080",
  --     "biometric_support": true
  --   }
  -- }

  registered_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, -- 이 사용자 프로파일 로우가 처음 생성된 시각 (첫 디바이스 등록 시)
  last_used_at TIMESTAMP,                                 -- 이 사용자의 어떤 디바이스든 마지막으로 사용된 시각 (애플리케이션에서 업데이트 필요)
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP -- 이 프로파일 정보가 마지막으로 수정된 시각 (trg_set_updated_at_user_device_profile 트리거로 자동 관리)
);

COMMENT ON TABLE user_device_profile IS '사용자가 Comfort Commit 서비스에 등록하거나 사용한 디바이스들의 목록 및 각 디바이스의 상세 프로필 정보를 저장합니다.';
COMMENT ON COLUMN user_device_profile.id IS 'user_info 테이블의 사용자 id를 참조하는 기본 키입니다.';
COMMENT ON COLUMN user_device_profile.device_uuids_array IS '사용자가 등록한 모든 디바이스의 고유 uuid를 문자열 배열로 저장합니다. 특정 디바이스 uuid 검색에 사용됩니다.';
COMMENT ON COLUMN user_device_profile.devices_info IS '각 디바이스의 상세 정보(이름, 타입, OS, 신뢰/차단 상태, 사용 통계 등)를 JSON 객체 배열 형태로 저장합니다. 각 객체는 "device_uuid"를 포함해야 합니다.';
COMMENT ON COLUMN user_device_profile.registered_at IS '이 사용자에 대한 디바이스 프로파일 레코드가 처음 생성된 시각입니다. 일반적으로 첫 디바이스가 등록될 때의 시점입니다.';
COMMENT ON COLUMN user_device_profile.last_used_at IS '이 사용자가 등록된 디바이스 중 어느 것이든 마지막으로 사용한 것으로 기록된 시각입니다. 애플리케이션 로직을 통해 주기적으로 업데이트될 수 있습니다.';
COMMENT ON COLUMN user_device_profile.updated_at IS '이 디바이스 프로파일 정보가 마지막으로 갱신된 시각입니다.';

-- user_device_profile 테이블 인덱스
-- id는 PRIMARY KEY이므로 자동으로 인덱싱됩니다.
CREATE INDEX uuidx_user_device_profile_device_uuids_gin ON user_device_profile USING GIN(device_uuids_array); -- 특정 device_uuid가 등록되었는지 빠르게 검색
-- devices_info JSONB 내부 특정 필드 검색이 자주 필요할 경우, 표현식 기반 GIN 인덱스 추가 고려 (스케일업 시)
-- 예: CREATE INDEX uuidx_user_device_profile_devices_info_device_uuid_gin ON user_device_profile USING GIN ((devices_info -> 'device_uuid'));
-- 예: CREATE INDEX uuidx_user_device_profile_devices_info_trusted_gin ON user_device_profile USING GIN ((devices_info -> 'is_trusted_device'));

-- updated_at 컬럼 자동 갱신 트리거
-- (참고: set_updated_at() 함수는 '00_common_functions_and_types.sql' 파일에 최종적으로 통합 정의될 예정)
CREATE TRIGGER trg_set_updated_at_user_device_profile
BEFORE UPDATE ON user_device_profile
FOR EACH ROW EXECUTE FUNCTION set_updated_at();