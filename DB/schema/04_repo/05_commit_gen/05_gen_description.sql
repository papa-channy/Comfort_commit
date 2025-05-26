-- =====================================================================================
-- 파일: 05_generated_technical_descriptions.sql
-- 모듈: 04_repo_module / 05_commit_generation (LLM 기반 커밋 메시지 생성 흐름)
-- 설명: 1차 LLM 호출을 통해 생성된 각 코드 요소(주로 함수 또는 클래스)에 대한
--       "기술 설명서"를 저장합니다. 이 설명서는 해당 코드 요소의 역할, 주요 로직,
--       변경의 의도, 잠재적 영향 등을 기술하며, 2차 LLM 호출(커밋 메시지 생성)의
--       중요한 입력 컨텍스트로 활용됩니다.
-- 대상 DB: PostgreSQL Primary RDB
-- 파티셔닝: 고려 가능 (request_uuid 또는 generation_timestamp 기준으로, 데이터가 매우 많을 경우)
-- MVP 중점사항: 요청 uuid 및 원본 코드 요소 참조, 생성된 설명서 텍스트, 사용된 LLM 모델 정보.
-- 스케일업 고려사항: RLS, 파티셔닝, 설명서 버전 관리, 사용자 피드백/수정 내역 추적, 설명서 품질 자동 평가 점수.
-- =====================================================================================

CREATE TABLE generated_technical_descriptions (
    tech_description_uuid id PRIMARY KEY DEFAULT gen_random_id(), -- 기술 설명서 레코드의 고유 식별자 (PK)

    request_uuid id NOT NULL REFERENCES commit_generation_requests(request_uuid) ON DELETE CASCADE,
    -- 이 기술 설명서가 생성된 원본 커밋 생성 요청 (commit_generation_requests.request_uuid 참조)

    element_instance_id id NOT NULL REFERENCES snapshot_code_element_instances(element_instance_id) ON DELETE CASCADE,
    -- 이 기술 설명서가 대상으로 하는 특정 스냅샷의 코드 요소 인스턴스
    -- (snapshot_code_element_instances.element_instance_id 참조)

    -- 생성된 기술 설명서 내용
    description_title TEXT,                            -- 기술 설명서의 제목 (선택적, 예: "함수 'calculate_price' 상세 분석")
    description_content TEXT NOT NULL,                 -- LLM이 생성한 기술 설명서 본문
                                                       -- (Markdown, 일반 텍스트 등 형식 지정 가능)
    content_format TEXT DEFAULT 'markdown',            -- 설명서 내용의 형식 (예: 'markdown', 'plaintext')

    -- 기술 설명서 생성에 사용된 LLM 정보
    llm_model_name TEXT NOT NULL,                      -- 설명서 생성에 사용된 LLM 모델 이름
    llm_model_version TEXT,                            -- 사용된 LLM 모델의 버전 (선택적)
    llm_generation_parameters JSONB,                   -- LLM 호출 시 사용된 주요 파라미터 (temperature, top_p 등)

    -- LLM 응답 관련 정보 (llm_request_log 와의 연관성 고려)
    llm_request_log_uuid BIGINT, -- REFERENCES llm_request_log(uuid) ON DELETE SET NULL, (02_llm_module/02_llm_request_log.sql 참조, 타입 BIGINT로 수정)
                             -- 실제 LLM API 호출 로그 uuid (비용, 토큰 사용량 등 상세 정보 추적용)

    -- 생성 및 상태 정보
    generation_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, -- 기술 설명서가 생성된 시각
    version INT DEFAULT 1,                               -- 설명서 버전 (수동 또는 자동 수정/개선 시 증가, 스케일업 시)
    is_current_version BOOLEAN DEFAULT TRUE,             -- 현재 사용되는 최신 버전의 설명서인지 여부 (스케일업 시)

    -- (스케일업) 사용자 피드백 또는 내부 평가 점수
    -- quality_score NUMERIC(3,2),                       -- 생성된 설명서의 품질 점수 (내부 평가 로직 또는 사용자 피드백 기반)
    -- user_review_status TEXT,                          -- 예: 'NOT_REVIEWED', 'APPROVED', 'NEEDS_REVISION'

    --  auditing
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE generated_technical_descriptions IS '1차 LLM 호출을 통해 각 주요 코드 요소에 대해 생성된 기술 설명서를 저장합니다.';
COMMENT ON COLUMN generated_technical_descriptions.tech_description_uuid IS '기술 설명서 레코드의 고유 id입니다.';
COMMENT ON COLUMN generated_technical_descriptions.request_uuid IS '이 기술 설명서가 생성된 원본 커밋 생성 요청의 id (commit_generation_requests.request_uuid 참조)입니다.';
COMMENT ON COLUMN generated_technical_descriptions.element_instance_id IS '이 기술 설명서가 설명하는 대상 코드 요소 인스턴스의 id (snapshot_code_element_instances.element_instance_id 참조)입니다.';
COMMENT ON COLUMN generated_technical_descriptions.description_title IS '생성된 기술 설명서의 제목입니다 (선택적).';
COMMENT ON COLUMN generated_technical_descriptions.description_content IS 'LLM이 생성한 기술 설명서의 본문 내용입니다.';
COMMENT ON COLUMN generated_technical_descriptions.content_format IS '기술 설명서 내용의 형식입니다 (예: markdown, plaintext).';
COMMENT ON COLUMN generated_technical_descriptions.llm_model_name IS '기술 설명서 생성에 사용된 LLM의 모델명입니다.';
COMMENT ON COLUMN generated_technical_descriptions.llm_model_version IS '사용된 LLM 모델의 버전입니다.';
COMMENT ON COLUMN generated_technical_descriptions.llm_generation_parameters IS 'LLM 호출 시 사용된 주요 생성 파라미터들을 JSONB 형태로 저장합니다.';
COMMENT ON COLUMN generated_technical_descriptions.llm_request_log_uuid IS '실제 LLM API 호출에 대한 로그 uuid (llm_request_log.uuid 참조, BIGINT 타입)입니다.';
COMMENT ON COLUMN generated_technical_descriptions.generation_timestamp IS '기술 설명서가 LLM에 의해 생성된 시각입니다.';
COMMENT ON COLUMN generated_technical_descriptions.version IS '기술 설명서의 버전 번호입니다 (스케일업 시 사용).';
COMMENT ON COLUMN generated_technical_descriptions.is_current_version IS '이 설명서가 해당 코드 요소에 대한 현재 유효한 최신 버전인지 여부를 나타냅니다 (스케일업 시 사용).';
COMMENT ON COLUMN generated_technical_descriptions.created_at IS '이 기술 설명서 레코드가 데이터베이스에 처음 생성된 시각입니다.';
COMMENT ON COLUMN generated_technical_descriptions.updated_at IS '이 기술 설명서 정보가 마지막으로 수정된 시각입니다.';


-- 인덱스
CREATE INDEX uuidx_gtd_request_uuid ON generated_technical_descriptions(request_uuid);
CREATE INDEX uuidx_gtd_element_instance_id ON generated_technical_descriptions(element_instance_id);
CREATE INDEX uuidx_gtd_request_element_instance ON generated_technical_descriptions(request_uuid, element_instance_id);
CREATE INDEX uuidx_gtd_llm_model_name ON generated_technical_descriptions(llm_model_name);
CREATE INDEX uuidx_gtd_llm_request_log_uuid ON generated_technical_descriptions(llm_request_log_uuid) WHERE llm_request_log_uuid IS NOT NULL;

-- (스케일업 시) 버전 관리를 위한 인덱스
-- CREATE INDEX uuidx_gtd_element_instance_version ON generated_technical_descriptions(element_instance_id, version DESC) WHERE is_current_version = TRUE;


-- FK 제약조건은 참조하는 테이블(llm_request_log)이 먼저 생성된 후 ALTER TABLE로 추가하는 것을 권장
-- ALTER TABLE generated_technical_descriptions ADD CONSTRAINT fk_gtd_llm_request_log FOREIGN KEY (llm_request_log_uuid) REFERENCES llm_request_log(uuid) ON DELETE SET NULL;


-- updated_at 컬럼 자동 갱신 트리거 (00_common_functions_and_types.sql 에 set_updated_at 함수 정의 가정)
CREATE TRIGGER trg_set_updated_at_generated_technical_descriptions
BEFORE UPDATE ON generated_technical_descriptions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();