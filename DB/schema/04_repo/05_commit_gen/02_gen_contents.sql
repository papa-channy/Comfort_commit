-- =====================================================================================
-- 파일: 02_generated_commit_contents.sql
-- 모듈: 04_repo_module / 05_commit_generation (LLM 기반 커밋 메시지 생성 흐름)
-- 설명: 2차 LLM 호출을 통해 생성된 커밋 메시지 초안과 관련된 정보를 저장합니다.
--       여기에는 생성된 커밋 메시지 본문, 사용된 LLM 모델 정보, 생성 시각,
--       그리고 이 초안이 어떤 커밋 생성 요청에 해당하는지를 나타내는 참조 정보가 포함됩니다.
--       사용자의 검토 및 수정을 거치기 전의 원본 LLM 생성 결과물입니다.
-- 대상 DB: PostgreSQL Primary RDB
-- 파티셔닝: 고려 가능 (request_uuid 또는 generation_timestamp 기준으로, 데이터가 매우 많을 경우)
-- MVP 중점사항: 요청 uuid 참조, 생성된 커밋 메시지(제목/본문), 사용된 LLM 모델 정보, 생성 시각.
-- 스케일업 고려사항: RLS, 파티셔닝, 다양한 커밋 메시지 포맷 지원(예: Conventional Commits 구조화 저장), 토큰 사용량, 비용 정보 연동, LLM 응답의 원본 JSON 저장.
-- =====================================================================================

CREATE TABLE generated_commit_contents (
    generated_content_uuid id PRIMARY KEY DEFAULT gen_random_id(), -- 생성된 커밋 콘텐츠의 고유 식별자 (PK)

    request_uuid id NOT NULL REFERENCES commit_generation_requests(request_uuid) ON DELETE CASCADE,
    -- 이 커밋 콘텐츠가 생성된 원본 커밋 생성 요청 (commit_generation_requests.request_uuid 참조)
    -- ON DELETE CASCADE: 원본 요청이 삭제되면, 해당 요청으로 생성된 커밋 초안도 함께 삭제

    -- 생성된 커밋 메시지 (LLM 결과물)
    commit_message_title TEXT,                             -- 커밋 메시지 제목 (요약 라인)
    commit_message_body TEXT,                              -- 커밋 메시지 본문 (상세 설명)
    commit_message_full TEXT NOT NULL,                     -- 제목과 본문을 포함한 전체 커밋 메시지 원본 텍스트
                                                           -- (파싱 또는 사용자 정의 템플릿 적용 후의 결과일 수 있음)

    -- 커밋 메시지 생성에 사용된 LLM 정보
    llm_model_name TEXT NOT NULL,                          -- 커밋 메시지 생성에 사용된 LLM 모델 이름
    llm_model_version TEXT,                                -- 사용된 LLM 모델의 버전 (선택적)
    llm_generation_parameters JSONB,                       -- LLM 호출 시 사용된 주요 파라미터 (temperature, top_p 등)

    -- LLM 응답 관련 정보 (llm_request_log 와의 연관성 고려)
    llm_request_log_uuid BIGINT, -- REFERENCES llm_request_log(uuid) ON DELETE SET NULL, (02_llm_module/02_llm_request_log.sql 참조, 타입 BIGINT로 수정)
                             -- 실제 LLM API 호출 로그 uuid (비용, 토큰 사용량 등 상세 정보 추적용)
    llm_output_raw JSONB,    -- LLM 응답의 원본 JSON 전체 (선택적, 디버깅 및 분석용)

    -- 생성 및 상태 정보
    generation_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, -- 커밋 메시지 초안이 생성된 시각
    is_edited_by_user BOOLEAN DEFAULT FALSE,             -- 이 초안이 사용자에 의해 수정되었는지 여부 (최초 생성 시 FALSE)
                                                         -- 실제 편집 내용은 finalized_commits 에서 관리되거나, 버전 관리 필요시 별도 테이블.
    user_feedback_score INT,                             -- 생성된 초안에 대한 사용자 만족도 점수 (1-5점 등, 선택적)
    user_feedback_notes TEXT,                            -- 사용자의 피드백 코멘트 (선택적)

    --  auditing
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE generated_commit_contents IS '2차 LLM 호출을 통해 생성된 커밋 메시지 초안 및 관련 정보를 저장합니다.';
COMMENT ON COLUMN generated_commit_contents.generated_content_uuid IS '생성된 커밋 콘텐츠의 고유 id입니다.';
COMMENT ON COLUMN generated_commit_contents.request_uuid IS '이 커밋 콘텐츠가 생성된 원본 커밋 생성 요청의 id (commit_generation_requests.request_uuid 참조)입니다.';
COMMENT ON COLUMN generated_commit_contents.commit_message_title IS 'LLM이 생성한 커밋 메시지의 제목(요약) 부분입니다.';
COMMENT ON COLUMN generated_commit_contents.commit_message_body IS 'LLM이 생성한 커밋 메시지의 본문(상세 설명) 부분입니다.';
COMMENT ON COLUMN generated_commit_contents.commit_message_full IS 'LLM이 생성한 전체 커밋 메시지 원본 텍스트입니다.';
COMMENT ON COLUMN generated_commit_contents.llm_model_name IS '커밋 메시지 생성에 사용된 LLM의 모델명입니다.';
COMMENT ON COLUMN generated_commit_contents.llm_model_version IS '사용된 LLM 모델의 버전입니다.';
COMMENT ON COLUMN generated_commit_contents.llm_generation_parameters IS 'LLM 호출 시 사용된 주요 생성 파라미터 (temperature, top_p 등)를 JSONB 형태로 저장합니다.';
COMMENT ON COLUMN generated_commit_contents.llm_request_log_uuid IS '실제 LLM API 호출에 대한 로그 uuid (llm_request_log.uuid 참조, BIGINT 타입)입니다. 토큰 사용량, 비용 등의 상세 정보 추적에 사용됩니다.';
COMMENT ON COLUMN generated_commit_contents.llm_output_raw IS 'LLM으로부터 받은 응답의 원본 JSON 전체입니다 (디버깅 및 상세 분석용, 선택적).';
COMMENT ON COLUMN generated_commit_contents.generation_timestamp IS '커밋 메시지 초안이 LLM에 의해 생성된 시각입니다.';
COMMENT ON COLUMN generated_commit_contents.is_edited_by_user IS '이 LLM 생성 초안이 사용자에 의해 수정되었는지 여부를 나타냅니다 (최초 생성 시 FALSE).';
COMMENT ON COLUMN generated_commit_contents.user_feedback_score IS '생성된 커밋 메시지 초안에 대한 사용자의 만족도 점수입니다 (선택적).';
COMMENT ON COLUMN generated_commit_contents.user_feedback_notes IS '생성된 초안에 대한 사용자의 구체적인 피드백 코멘트입니다 (선택적).';
COMMENT ON COLUMN generated_commit_contents.created_at IS '이 커밋 콘텐츠 레코드가 데이터베이스에 처음 생성된 시각입니다.';
COMMENT ON COLUMN generated_commit_contents.updated_at IS '이 커밋 콘텐츠 정보가 마지막으로 수정된 시각입니다.';


-- 인덱스
CREATE INDEX uuidx_gcc_request_uuid ON generated_commit_contents(request_uuid);
CREATE INDEX uuidx_gcc_llm_model_name ON generated_commit_contents(llm_model_name);
CREATE INDEX uuidx_gcc_generation_timestamp ON generated_commit_contents(generation_timestamp DESC);
CREATE INDEX uuidx_gcc_is_edited_by_user ON generated_commit_contents(is_edited_by_user);
CREATE INDEX uuidx_gcc_llm_request_log_uuid ON generated_commit_contents(llm_request_log_uuid) WHERE llm_request_log_uuid IS NOT NULL;


-- FK 제약조건은 참조하는 테이블(llm_request_log)이 먼저 생성된 후 ALTER TABLE로 추가하는 것을 권장
-- ALTER TABLE generated_commit_contents ADD CONSTRAINT fk_gcc_llm_request_log FOREIGN KEY (llm_request_log_uuid) REFERENCES llm_request_log(uuid) ON DELETE SET NULL;


-- updated_at 컬럼 자동 갱신 트리거 (00_common_functions_and_types.sql 에 set_updated_at 함수 정의 가정)
CREATE TRIGGER trg_set_updated_at_generated_commit_contents
BEFORE UPDATE ON generated_commit_contents
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();