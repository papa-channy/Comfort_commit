-- =====================================================================================
-- 파일: 03_finalized_commits.sql
-- 모듈: 04_repo_module / 05_commit_generation (LLM 기반 커밋 메시지 생성 흐름)
-- 설명: 사용자가 Comfort Commit 시스템을 통해 최종적으로 검토, 수정 및 확정한
--       커밋 메시지와 관련 승인 정보를 저장합니다. 이 정보는 실제 Git 커밋 실행의 기준이 되며,
--       사용자 행동 분석 및 시스템 감사에 활용됩니다.
-- 대상 DB: PostgreSQL Primary RDB
-- 파티셔닝: 고려 가능 (finalized_timestamp 기준으로, 데이터가 매우 많을 경우)
-- MVP 중점사항: 원본 요청/초안 참조, 최종 커밋 메시지, 승인자 정보, 승인 시각, 편집 여부.
-- 스케일업 고려사항: RLS, 파티셔닝, Git 커밋 해시(SHA) 저장, 푸시(push) 상태 추적, 다양한 승인 워크플로우 지원.
-- =====================================================================================

CREATE TABLE finalized_commits (
    finalized_commit_id id PRIMARY KEY DEFAULT gen_random_id(), -- 최종 확정된 커밋의 고유 식별자 (PK)

    request_uuid id NOT NULL REFERENCES commit_generation_requests(request_uuid) ON DELETE RESTRICT,
    -- 이 최종 커밋의 원본이 되는 커밋 생성 요청 (commit_generation_requests.request_uuid 참조)
    -- ON DELETE RESTRICT: 최종 확정된 커밋이 있는 요청은 임의로 삭제할 수 없도록 제한 (감사 추적)

    generated_content_uuid id NOT NULL REFERENCES generated_commit_contents(generated_content_uuid) ON DELETE RESTRICT,
    -- 사용자가 검토한 LLM 생성 커밋 메시지 초안 (generated_commit_contents.generated_content_uuid 참조)
    -- ON DELETE RESTRICT: 최종 확정된 커밋의 기반이 된 초안은 임의로 삭제할 수 없도록 제한

    -- 최종 확정된 커밋 메시지
    final_commit_message_title TEXT,
    final_commit_message_body TEXT,
    final_commit_message_full TEXT NOT NULL, -- 사용자가 최종 확정한 전체 커밋 메시지

    -- 승인자 및 승인 정보
    finalized_by_user_id id NOT NULL REFERENCES user_info(id) ON DELETE SET NULL,
    -- 이 커밋을 최종 확정한 사용자 (user_info.id 참조)
    finalized_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, -- 최종 확정 시각
    approval_source TEXT,                         -- 승인 경로/수단 (예: 'WEB_UI_APPROVAL', 'MOBILE_APP_SWIPE', 'SLACK_INTERACTION', 'AUTO_APPROVED_BY_RULE')

    was_edited_from_generated BOOLEAN NOT NULL DEFAULT FALSE, -- LLM 생성 초안에서 사용자에 의해 수정되었는지 여부
                                                          -- TRUE이면 generated_commit_contents.commit_message_full 과 다름.

    -- 실제 Git 커밋 관련 정보 (Git 커밋 실행 후 업데이트)
    git_commit_sha TEXT UNIQUE,                   -- 실제 Git 리포지토리에 커밋된 후 생성된 SHA-1 해시 (선택적, 커밋 후 업데이트)
                                                  -- UNIQUE 제약으로 동일 SHA 중복 방지
    git_commit_timestamp TIMESTAMP WITH TIME ZONE,  -- 실제 Git 커밋 시각 (선택적)
    git_push_status push_status_enum,             -- Git push 상태 (04_repo_module/00_repo_enums_and_types.sql 정의 예정, 선택적)
                                                  -- 예: 'NOT_PUSHED', 'PUSH_PENDING', 'PUSH_SUCCESSFUL', 'PUSH_FAILED'
    git_push_timestamp TIMESTAMP WITH TIME ZONE,    -- Git push 시각 (선택적)
    git_error_message TEXT,                       -- Git 작업(커밋/푸시) 실패 시 오류 메시지

    -- 추가 메타데이터
    review_notes TEXT,                            -- 최종 확정 과정에서의 사용자 또는 시스템 메모

    --  auditing
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE finalized_commits IS '사용자가 Comfort Commit을 통해 최종 검토 및 확정한 커밋 메시지와 관련 승인 정보를 저장합니다.';
COMMENT ON COLUMN finalized_commits.finalized_commit_id IS '최종 확정된 커밋의 고유 id입니다.';
COMMENT ON COLUMN finalized_commits.request_uuid IS '이 최종 커밋의 원본 커밋 생성 요청 id (commit_generation_requests.request_uuid 참조)입니다.';
COMMENT ON COLUMN finalized_commits.generated_content_uuid IS '사용자가 검토한 LLM 생성 커밋 메시지 초안의 id (generated_commit_contents.generated_content_uuid 참조)입니다.';
COMMENT ON COLUMN finalized_commits.final_commit_message_title IS '사용자가 최종 확정한 커밋 메시지의 제목 부분입니다.';
COMMENT ON COLUMN finalized_commits.final_commit_message_body IS '사용자가 최종 확정한 커밋 메시지의 본문 부분입니다.';
COMMENT ON COLUMN finalized_commits.final_commit_message_full IS '사용자가 최종 확정한 전체 커밋 메시지 텍스트입니다.';
COMMENT ON COLUMN finalized_commits.finalized_by_user_id IS '이 커밋을 최종 확정한 사용자의 id (user_info.id 참조)입니다.';
COMMENT ON COLUMN finalized_commits.finalized_timestamp IS '사용자가 커밋을 최종 확정한 시각입니다.';
COMMENT ON COLUMN finalized_commits.approval_source IS '커밋이 승인된 경로 또는 수단을 나타냅니다 (예: 웹 UI, 모바일 앱).';
COMMENT ON COLUMN finalized_commits.was_edited_from_generated IS 'LLM이 생성한 초안에서 사용자에 의해 내용이 수정되었는지 여부를 나타냅니다.';
COMMENT ON COLUMN finalized_commits.git_commit_sha IS '실제 Git 리포지토리에 반영된 커밋의 SHA-1 해시값입니다 (커밋 실행 후 업데이트).';
COMMENT ON COLUMN finalized_commits.git_commit_timestamp IS '실제 Git 커밋이 이루어진 시각입니다.';
COMMENT ON COLUMN finalized_commits.git_push_status IS '연결된 Git 리포지토리로의 push 상태입니다 (04_repo_module/00_repo_enums_and_types.sql 정의된 push_status_enum 값).';
COMMENT ON COLUMN finalized_commits.git_push_timestamp IS 'Git push가 이루어진 시각입니다.';
COMMENT ON COLUMN finalized_commits.git_error_message IS 'Git 커밋 또는 푸시 작업 중 오류 발생 시 해당 오류 메시지를 저장합니다.';
COMMENT ON COLUMN finalized_commits.review_notes IS '최종 확정 과정에 대한 추가적인 사용자 또는 시스템 메모입니다.';
COMMENT ON COLUMN finalized_commits.created_at IS '이 최종 커밋 레코드가 데이터베이스에 처음 생성된 시각입니다.';
COMMENT ON COLUMN finalized_commits.updated_at IS '이 최종 커밋 정보가 마지막으로 수정된 시각입니다.';


-- 인덱스
CREATE INDEX uuidx_fc_request_uuid ON finalized_commits(request_uuid);
CREATE INDEX uuidx_fc_generated_content_uuid ON finalized_commits(generated_content_uuid);
CREATE INDEX uuidx_fc_finalized_by_user_id ON finalized_commits(finalized_by_user_id);
CREATE INDEX uuidx_fc_finalized_timestamp ON finalized_commits(finalized_timestamp DESC);
CREATE INDEX uuidx_fc_git_commit_sha ON finalized_commits(git_commit_sha) WHERE git_commit_sha IS NOT NULL;
CREATE INDEX uuidx_fc_git_push_status ON finalized_commits(git_push_status);

-- updated_at 컬럼 자동 갱신 트리거 (00_common_functions_and_types.sql 에 set_updated_at 함수 정의 가정)
CREATE TRIGGER trg_set_updated_at_finalized_commits
BEFORE UPDATE ON finalized_commits
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();
