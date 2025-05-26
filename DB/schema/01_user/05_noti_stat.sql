-- =====================================================================================
-- 파일: 05_user_noti_stat.sql
-- 모듈: 01_user_module (사용자 모듈)
-- 설명: 사용자별, 알림 채널별 누적 통계(발송/클릭 횟수)를 관리합니다.
-- 대상 DB: PostgreSQL Primary RDB (사용자 통계 데이터)
-- 파티셔닝: 없음 (사용자당 1개의 로우 또는 익명화된 통합 로우)
-- MVP 중점사항: 사용자별 단일 로우 구조 (또는 탈퇴자 익명화), 배열 타입을 사용한 채널별 통계 집계, 필수 인덱스.
-- 스케일업 고려사항: RLS 적용, 채널 수가 매우 많아질 경우 배열 관리의 복잡성 및 성능 검토, 고급 분석을 위한 데이터 웨어하우스 연동.
-- 개인정보보호: 사용자 탈퇴 시 id는 NULL로 설정되어 통계는 익명으로 보존될 수 있도록 설계.
-- =====================================================================================

-- 사용자 알림 통계 테이블
CREATE TABLE user_noti_stat (
  uuid BIGSERIAL PRIMARY KEY,                                -- 내부 자동 증가 uuid
  id id UNIQUE REFERENCES user_info(id) ON DELETE SET NULL, -- 사용자 식별자, 탈퇴 시 NULL로 설정되어 익명화. NULL이 아닐 경우 UNIQUE.
  -- UNIQUE 제약은 id가 NULL이 아닐 때만 적용됩니다.

  channels_used TEXT[] DEFAULT ARRAY[]::TEXT[],           -- 사용된 알림 채널 목록 (예: ['email', 'slack'])
  sent_counts INTEGER[] DEFAULT ARRAY[]::INTEGER[],       -- 각 채널별 발송 횟수 (channels_used 배열 순서와 매칭)
  clicked_counts INTEGER[] DEFAULT ARRAY[]::INTEGER[],    -- 각 채널별 클릭(또는 반응) 횟수 (channels_used 배열 순서와 매칭)
  last_activity_at TIMESTAMP,                             -- 이 통계 레코드와 관련된 마지막 알림 활동 시각
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, -- 이 통계 레코드가 처음 생성된 시각
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP -- 이 통계 레코드가 마지막으로 수정된 시각
);

COMMENT ON TABLE user_noti_stat IS '사용자별(활성 사용자) 또는 익명화된(탈퇴 사용자) 알림 채널별 누적 통계를 저장합니다.';
COMMENT ON COLUMN user_noti_stat.uuid IS '이 통계 레코드의 고유 식별자입니다.';
COMMENT ON COLUMN user_noti_stat.id IS 'user_info 테이블의 사용자 id를 참조합니다. 사용자가 탈퇴하면 이 값은 NULL로 설정되어 통계는 익명으로 보존될 수 있습니다. NULL이 아닌 경우 고유해야 합니다.';
COMMENT ON COLUMN user_noti_stat.channels_used IS '통계가 집계된 알림 채널들의 목록입니다.';
COMMENT ON COLUMN user_noti_stat.sent_counts IS 'channels_used 배열에 대응하는 각 채널별 총 알림 발송 횟수입니다.';
COMMENT ON COLUMN user_noti_stat.clicked_counts IS 'channels_used 배열에 대응하는 각 채널별 총 알림 클릭(또는 유효 반응) 횟수입니다.';
COMMENT ON COLUMN user_noti_stat.last_activity_at IS '이 통계와 관련된 마지막 알림 발송 또는 클릭 활동이 있었던 시각입니다.';
COMMENT ON COLUMN user_noti_stat.created_at IS '이 통계 레코드가 데이터베이스에 처음 생성된 시각입니다.';
COMMENT ON COLUMN user_noti_stat.updated_at IS '이 통계 정보가 마지막으로 갱신된 시각입니다.';


-- user_noti_stat 테이블 인덱스
CREATE INDEX uuidx_user_noti_stat_id ON user_noti_stat(id) WHERE id IS NOT NULL; -- 활성 사용자 통계 조회용
-- 채널 목록(channels_used) 내 특정 채널 포함 여부 검색이 필요할 경우 GIN 인덱스 고려 (선택적)
-- 예: CREATE INDEX uuidx_user_noti_stat_channels_gin ON user_noti_stat USING GIN(channels_used);

CREATE TRIGGER trg_set_updated_at_user_noti_stat
BEFORE UPDATE ON user_noti_stat
FOR EACH ROW EXECUTE FUNCTION set_updated_at();