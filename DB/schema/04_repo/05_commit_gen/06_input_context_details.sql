-- =====================================================================================
-- 파일: 06_llm_input_context_details.sql
-- 모듈: 04_repo_module / 05_commit_generation (LLM 기반 커밋 메시지 생성 흐름)
-- 설명: 2차 LLM 호출(커밋 메시지 생성) 시 사용된 구체적인 입력 컨텍스트 요소들의
--       참조 정보를 상세히 기록합니다. 이를 통해 어떤 README 요약, 기술 설명서, Diff 조각,
--       파일 분석 메트릭 등이 특정 커밋 메시지 생성에 영향을 미쳤는지 추적하고 분석할 수 있습니다.
--       `commit_generation_requests.context_references_json`의 내용을 보다 정형화하여 관리하는 역할을 합니다.
-- 대상 DB: PostgreSQL Primary RDB
-- 파티셔닝: 고려 가능 (request_uuid 또는 created_at 기준으로, 데이터가 매우 많을 경우)
-- MVP 중점사항: 요청 uuid 참조, 컨텍스트 요소 타입(ENUM), 해당 요소의 참조 uuid, 포함 순서/중요도.
-- 스케일업 고려사항: RLS, 파티셔닝, 각 컨텍스트 요소의 부분 사용 정보(예: 기술 설명서의 특정 문단만 사용), 컨텍스트 조합 전략 로깅.
-- =====================================================================================

CREATE TABLE llm_input_context_details (
    context_detail_uuid id PRIMARY KEY DEFAULT gen_random_id(), -- LLM 입력 컨텍스트 상세 항목의 고유 식별자 (PK)

    request_uuid id NOT NULL REFERENCES commit_generation_requests(request_uuid) ON DELETE CASCADE,
    -- 이 입력 컨텍스트가 사용된 커밋 생성 요청 (commit_generation_requests.request_uuid 참조)

    llm_call_stage llm_call_stage_enum NOT NULL DEFAULT 'COMMIT_MESSAGE_GENERATION', -- 이 컨텍스트가 사용된 LLM 호출 단계
                                                                                  -- (04_repo_module/00_repo_enums_and_types.sql 정의 예정)
                                                                                  -- 주로 'COMMIT_MESSAGE_GENERATION'이 되겠지만, 향후 다른 LLM 호출 단계에서도 활용 가능

    context_element_type llm_input_context_type_enum NOT NULL, -- 입력 컨텍스트 요소의 타입
                                                               -- (04_repo_module/00_repo_enums_and_types.sql 정의 예정)
                                                               -- 예: 'TECHNICAL_DESCRIPTION', 'DIFF_FRAGMENT', 'README_SUMMARY', 'FILE_ANALYSIS_METRIC', 'CODE_ELEMENT_RELATION', 'USER_INSTRUCTION'

    context_element_reference_uuid id NOT NULL,       -- 해당 컨텍스트 요소의 실제 데이터가 저장된 테이블의 레코드 uuid (FK는 타입별로 동적으로 설정 어려움)
                                                       -- 예: generated_technical_descriptions.tech_description_uuid,
                                                       --     file_diff_fragments.diff_fragment_uuid,
                                                       --     (README 요약 저장 테이블).readme_summary_uuid 등

    -- 컨텍스트 포함 순서 또는 가중치 (선택적)
    order_in_prompt INT,                              -- 프롬프트 내에서 이 컨텍스트 요소가 포함된 순서 (선택적)
    importance_score NUMERIC(5,4),                    -- 이 컨텍스트 요소의 중요도 또는 가중치 (선택적)

    -- 사용된 컨텍스트의 특정 부분에 대한 정보 (스케일업 시)
    -- element_subset_uuidentifier TEXT,                -- 예: 기술 설명서의 "주요 변경점" 섹션만 사용, Diff의 특정 Hunk만 사용 등

    --  auditing
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- 동일 요청, 동일 LLM 호출 단계에서 동일 타입의 동일 참조 uuid가 중복으로 들어가지 않도록 (보통은 발생 안 함)
    CONSTRAINT uq_llm_input_context_detail UNIQUE (request_uuid, llm_call_stage, context_element_type, context_element_reference_uuid)
);

COMMENT ON TABLE llm_input_context_details IS '2차 LLM 호출(커밋 메시지 생성)에 사용된 각 입력 컨텍스트 요소의 참조 정보를 상세히 기록합니다.';
COMMENT ON COLUMN llm_input_context_details.context_detail_uuid IS 'LLM 입력 컨텍스트 상세 항목의 고유 id입니다.';
COMMENT ON COLUMN llm_input_context_details.request_uuid IS '이 입력 컨텍스트가 사용된 커밋 생성 요청의 id (commit_generation_requests.request_uuid 참조)입니다.';
COMMENT ON COLUMN llm_input_context_details.llm_call_stage IS '이 컨텍스트 정보가 사용된 LLM 호출의 단계를 나타냅니다 (04_repo_module/00_repo_enums_and_types.sql 정의된 llm_call_stage_enum 값, 주로 커밋 메시지 생성 단계).';
COMMENT ON COLUMN llm_input_context_details.context_element_type IS '입력된 컨텍스트 요소의 타입을 나타냅니다 (04_repo_module/00_repo_enums_and_types.sql 정의된 llm_input_context_type_enum 값).';
COMMENT ON COLUMN llm_input_context_details.context_element_reference_uuid IS '해당 컨텍스트 요소의 원본 데이터가 저장된 테이블의 레코드 id입니다. 타입에 따라 참조하는 테이블이 다릅니다.';
COMMENT ON COLUMN llm_input_context_details.order_in_prompt IS '프롬프트 내에서 이 컨텍스트 요소가 포함된 상대적인 순서입니다 (선택적).';
COMMENT ON COLUMN llm_input_context_details.importance_score IS '이 컨텍스트 요소의 상대적인 중요도 또는 가중치 점수입니다 (선택적).';
COMMENT ON COLUMN llm_input_context_details.created_at IS '이 컨텍스트 상세 정보 레코드가 데이터베이스에 처음 생성된 시각입니다.';
COMMENT ON COLUMN llm_input_context_details.updated_at IS '이 컨텍스트 상세 정보 레코드가 마지막으로 수정된 시각입니다.';
COMMENT ON CONSTRAINT uq_llm_input_context_detail ON llm_input_context_details IS '동일 요청, 동일 LLM 호출 단계에서 특정 타입의 특정 참조 uuid를 가진 컨텍스트 요소는 유일해야 합니다.';


-- 인덱스
CREATE INDEX uuidx_licd_request_uuid_stage ON llm_input_context_details(request_uuid, llm_call_stage);
CREATE INDEX uuidx_licd_context_type_ref_uuid ON llm_input_context_details(context_element_type, context_element_reference_uuid);

-- updated_at 컬럼 자동 갱신 트리거 (00_common_functions_and_types.sql 에 set_updated_at 함수 정의 가정)
CREATE TRIGGER trg_set_updated_at_llm_input_context_details
BEFORE UPDATE ON llm_input_context_details
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();
