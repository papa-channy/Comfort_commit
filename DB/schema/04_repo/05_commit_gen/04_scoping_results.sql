-- =====================================================================================
-- 파일: 04_scoping_results.sql
-- 모듈: 04_repo_module / 05_commit_generation (LLM 기반 커밋 메시지 생성 흐름)
-- 설명: 커밋 메시지 생성을 위한 컨텍스트 범위 결정을 위해 수행된 스코핑(Scoping) 과정 및
--       그 결과를 상세히 기록합니다. 여기에는 정적 분석(예: Jaccard, Simhash) 기반의
--       1차 스코핑과 임베딩 기반의 의미론적 유사도 분석을 통한 2차 스코핑 결과가 포함될 수 있습니다.
--       각 스코핑 단계에서 어떤 코드 요소들이 어떤 기준으로 선택되었는지, 각 요소의 점수 등을 저장합니다.
-- 대상 DB: PostgreSQL Primary RDB
-- 파티셔닝: 고려 가능 (request_uuid 또는 scoping_timestamp 기준으로, 데이터가 매우 많을 경우)
-- MVP 중점사항: 요청 uuid 참조, 스코핑 단계 구분, 대상 코드 요소, 사용된 분석 방법, 유사도/관련도 점수, 최종 선택 여부.
-- 스케일업 고려사항: RLS, 파티셔닝, 다양한 스코핑 알고리즘 지원, 단계별 임계값 저장, 스코핑 결과의 시각화 지원 데이터.
-- =====================================================================================

CREATE TABLE scoping_results (
    scoping_result_entry_uuid id PRIMARY KEY DEFAULT gen_random_id(), -- 스코핑 결과 각 항목의 고유 식별자 (PK)

    request_uuid id NOT NULL REFERENCES commit_generation_requests(request_uuid) ON DELETE CASCADE,
    -- 이 스코핑 결과가 속한 커밋 생성 요청 (commit_generation_requests.request_uuid 참조)

    scoping_run_uuid id NOT NULL,               -- 동일 요청 내에서 여러 번의 스코핑 실행(run)이 있을 경우 이를 그룹화하는 uuid
                                                -- (예: 사용자가 파라미터를 변경하여 재실행하거나, A/B 테스트 시)
                                                -- 이 uuid를 `commit_generation_requests.scoping_result_uuid` 에서 참조할 수 있음.

    scoping_stage_name TEXT NOT NULL,           -- 스코핑 단계 이름 (예: 'INITIAL_CANDuuidATES', 'STATIC_ANALYSIS_FILTER', 'EMBEDDING_SIMILARITY_RANKING', 'FINAL_CONTEXT_SET')
    scoping_stage_order INT NOT NULL,           -- 스코핑 단계의 순서 (예: 1, 2, 3...)

    -- 스코핑 대상이 되는 코드 요소 인스턴스
    target_element_instance_id id NOT NULL REFERENCES snapshot_code_element_instances(element_instance_id) ON DELETE CASCADE,
    -- 스코핑의 대상이 된 코드 요소 인스턴스 (snapshot_code_element_instances.element_instance_id 참조)

    -- 스코핑에 사용된 기준 요소 (선택적, 예: 변경된 메인 함수)
    base_element_instance_id id REFERENCES snapshot_code_element_instances(element_instance_id) ON DELETE SET NULL,
    -- 이 대상 요소가 어떤 기준 요소(예: 직접 변경된 함수)와의 관계/유사도로 스코핑되었는지 (선택적)

    -- 스코핑 방법 및 결과
    scoping_method TEXT NOT NULL,               -- 사용된 스코핑 방법/알고리즘 (예: 'JACCARD_SIMILARITY', 'SIMHASH_DISTANCE', 'CODEBERT_COSINE_SIMILARITY', 'CALL_GRAPH_NEIGHBOR_LEVEL_1')
    score NUMERIC,                              -- 해당 방법에 따른 점수 (유사도, 관련도, 거리 등)
    rank_within_stage INT,                      -- 해당 스코핑 단계 내에서의 순위 (점수 기반)

    is_selected_for_next_stage BOOLEAN DEFAULT FALSE, -- 이 코드 요소가 다음 스코핑 단계 또는 최종 컨텍스트로 선택되었는지 여부
    selection_reason TEXT,                      -- 선택 또는 제외된 이유 (선택적)

    -- 스코핑 실행 관련 메타데이터
    scoping_parameters JSONB,                   -- 해당 스코핑 단계/방법 실행 시 사용된 파라미터 (예: 임계값, Top-N 개수)
    scoping_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, -- 이 스코핑 결과 항목이 기록된 시각

    --  auditing
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- 동일 스코핑 실행(run) 내에서, 동일 단계, 동일 타겟 요소에 대한 중복 결과 방지 (스코핑 방법에 따라 키 추가 필요 가능)
    CONSTRAINT uq_scoping_result_run_stage_target UNIQUE (scoping_run_uuid, scoping_stage_name, target_element_instance_id, scoping_method)
);

COMMENT ON TABLE scoping_results IS '커밋 생성 요청에 대해 수행된 각 스코핑 단계의 결과(선별된 코드 요소 및 점수 등)를 상세히 기록합니다.';
COMMENT ON COLUMN scoping_results.scoping_result_entry_uuid IS '스코핑 결과 각 항목의 고유 id입니다.';
COMMENT ON COLUMN scoping_results.request_uuid IS '이 스코핑 결과가 속한 커밋 생성 요청의 id (commit_generation_requests.request_uuid 참조)입니다.';
COMMENT ON COLUMN scoping_results.scoping_run_uuid IS '동일 요청 내 여러 스코핑 실행을 그룹화하는 uuid입니다. 이 uuid를 `commit_generation_requests.scoping_result_uuid` 에서 참조합니다.';
COMMENT ON COLUMN scoping_results.scoping_stage_name IS '스코핑 단계의 이름입니다 (예: 정적 분석, 임베딩 유사도).';
COMMENT ON COLUMN scoping_results.scoping_stage_order IS '스코핑 단계의 순서를 나타냅니다.';
COMMENT ON COLUMN scoping_results.target_element_instance_id IS '스코핑 대상이 된 코드 요소 인스턴스의 id (snapshot_code_element_instances.element_instance_id 참조)입니다.';
COMMENT ON COLUMN scoping_results.base_element_instance_id IS '스코핑의 기준이 된 코드 요소 인스턴스의 id (선택적, snapshot_code_element_instances.element_instance_id 참조)입니다.';
COMMENT ON COLUMN scoping_results.scoping_method IS '사용된 스코핑 방법 또는 알고리즘의 이름입니다.';
COMMENT ON COLUMN scoping_results.score IS '스코핑 방법에 따른 점수 (유사도, 관련도 등)입니다.';
COMMENT ON COLUMN scoping_results.rank_within_stage IS '해당 스코핑 단계 내에서의 순위입니다.';
COMMENT ON COLUMN scoping_results.is_selected_for_next_stage IS '이 코드 요소가 다음 단계 또는 최종 컨텍스트로 선택되었는지 여부입니다.';
COMMENT ON COLUMN scoping_results.selection_reason IS '선택 또는 제외된 구체적인 이유입니다 (선택적).';
COMMENT ON COLUMN scoping_results.scoping_parameters IS '해당 스코핑 실행 시 사용된 파라미터 (임계값, Top-N 등)를 JSONB로 저장합니다.';
COMMENT ON COLUMN scoping_results.scoping_timestamp IS '이 스코핑 결과 항목이 기록된 시각입니다.';
COMMENT ON COLUMN scoping_results.created_at IS '이 스코핑 결과 레코드가 데이터베이스에 처음 생성된 시각입니다.';
COMMENT ON COLUMN scoping_results.updated_at IS '이 스코핑 결과 레코드 정보가 마지막으로 수정된 시각입니다.';
COMMENT ON CONSTRAINT uq_scoping_result_run_stage_target ON scoping_results IS '하나의 스코핑 실행 내에서, 동일 단계, 동일 타겟 요소에 대해 동일한 스코핑 방법으로 중복된 결과가 나올 수 없습니다.';


-- 인덱스
CREATE INDEX uuidx_sr_request_uuid ON scoping_results(request_uuid);
CREATE INDEX uuidx_sr_scoping_run_uuid ON scoping_results(scoping_run_uuid);
CREATE INDEX uuidx_sr_target_element_instance_id ON scoping_results(target_element_instance_id);
CREATE INDEX uuidx_sr_stage_order_rank ON scoping_results(scoping_run_uuid, scoping_stage_order, rank_within_stage);
CREATE INDEX uuidx_sr_is_selected_for_next_stage ON scoping_results(is_selected_for_next_stage) WHERE is_selected_for_next_stage = TRUE;
CREATE INDEX uuidx_sr_scoping_method ON scoping_results(scoping_method);

-- updated_at 컬럼 자동 갱신 트리거 (00_common_functions_and_types.sql 에 set_updated_at 함수 정의 가정)
CREATE TRIGGER trg_set_updated_at_scoping_results
BEFORE UPDATE ON scoping_results
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();