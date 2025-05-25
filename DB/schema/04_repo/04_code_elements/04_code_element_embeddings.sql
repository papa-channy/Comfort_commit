-- =====================================================================================
-- 파일: 04_code_element_embeddings.sql
-- 모듈: 04_repo_module / 04_code_elements (함수/클래스 등 코드 요소 단위 정보)
-- 설명: 특정 스냅샷 시점의 코드 요소 인스턴스에 대해 계산된 임베딩 벡터와,
--       다른 코드 요소 인스턴스와의 계산된 유사도 점수를 저장합니다.
--       (예: Code2Vec, AST 기반 임베딩, Sentence-BERT 등 다양한 모델 활용 가능)
--       이 정보는 의미론적 유사도 기반 스코핑 및 관련 코드 추천 등에 활용됩니다.
-- 대상 DB: PostgreSQL Primary RDB (pgvector 확장 필요)
-- 파티셔닝: 고려 가능 (element_instance_uuid 또는 embedding_model_name 기준으로, 데이터가 매우 많을 경우)
-- MVP 중점사항: 코드 요소 인스턴스 참조, 임베딩 모델 정보, 벡터 값, (선택적) 주요 유사도 관계 기록.
-- 스케일업 고려사항: RLS, 파티셔닝, 다양한 임베딩 모델 지원, 근사 최근접 이웃(ANN) 검색 최적화.
-- =====================================================================================

-- pgvector 확장이 설치되어 있어야 `vector` 타입을 사용할 수 있습니다.
-- CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE code_element_embeddings (
    embedding_id UUID PRIMARY KEY DEFAULT gen_random_uuid(), -- 임베딩 레코드의 고유 식별자 (PK)

    element_instance_uuid UUID NOT NULL REFERENCES snapshot_code_element_instances(element_instance_uuid) ON DELETE CASCADE,
    -- 이 임베딩이 계산된 대상 코드 요소 인스턴스
    -- (snapshot_code_element_instances.element_instance_uuid 참조)

    embedding_model_name TEXT NOT NULL,        -- 사용된 임베딩 모델의 이름 (예: 'code2vec_cbow', 'sentence-bert-base-nli-mean-tokens', 'text-embedding-ada-002')
    embedding_model_version TEXT,              -- 사용된 임베딩 모델의 버전 (선택적)
    vector_dimensions INT NOT NULL,            -- 임베딩 벡터의 차원 수 (예: 128, 768, 1536)

    embedding_vector VECTOR(1536),             -- 실제 임베딩 벡터 값 (pgvector 타입 사용, 차원 수는 최대값 기준으로 설정 후 모델별로 조절)
                                               -- 차원 수는 가장 큰 모델 기준으로 설정하고, 작은 차원의 벡터는 패딩하거나 별도 컬럼/테이블로 관리 가능.
                                               -- 또는 모델별로 테이블을 분리하거나, JSONB에 저장하는 방식도 고려 가능 (검색 성능에 영향).
                                               -- MVP에서는 일단 최대 차원수 하나로 통일하고, 실제 사용 시 모델별 최적화.

    -- (선택적) 이 임베딩과 가장 유사한 Top-N개의 다른 코드 요소 인스턴스와의 유사도 점수 저장
    -- 이는 스코핑 결과 테이블(05_commit_generation/04_scoping_results.sql)로 이동하거나 중복 저장될 수 있음.
    -- 또는 자주 사용되는 유사도 쌍을 캐시하는 용도로 활용 가능.
    -- top_n_similar_elements JSONB,
    -- 예: [
    --   {"target_element_instance_uuid": "uuid_xyz", "similarity_score": 0.95, "rank": 1},
    --   {"target_element_instance_uuid": "uuid_abc", "similarity_score": 0.92, "rank": 2}
    -- ]

    -- 임베딩 계산에 사용된 소스 코드의 해시값 (내용 변경 시 재계산 여부 판단용, 선택적)
    source_code_checksum TEXT,

    --  auditing
    generated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, -- 임베딩이 생성된 시각
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE code_element_embeddings IS '특정 스냅샷 시점의 코드 요소 인스턴스에 대한 임베딩 벡터 및 관련 정보를 저장합니다.';
COMMENT ON COLUMN code_element_embeddings.embedding_id IS '임베딩 레코드의 고유 UUID입니다.';
COMMENT ON COLUMN code_element_embeddings.element_instance_uuid IS '임베딩이 계산된 코드 요소 인스턴스의 UUID입니다.';
COMMENT ON COLUMN code_element_embeddings.embedding_model_name IS '임베딩 생성에 사용된 모델의 이름입니다.';
COMMENT ON COLUMN code_element_embeddings.embedding_model_version IS '사용된 임베딩 모델의 버전입니다.';
COMMENT ON COLUMN code_element_embeddings.vector_dimensions IS '임베딩 벡터의 차원 수입니다.';
COMMENT ON COLUMN code_element_embeddings.embedding_vector IS '계산된 실제 임베딩 벡터 값입니다 (pgvector 타입).';
-- COMMENT ON COLUMN code_element_embeddings.top_n_similar_elements IS '이 임베딩과 가장 유사한 Top-N 코드 요소 인스턴스 및 유사도 점수를 JSONB 형태로 저장합니다 (선택적).';
COMMENT ON COLUMN code_element_embeddings.source_code_checksum IS '임베딩 계산의 기반이 된 소스 코드의 체크섬입니다 (선택적).';
COMMENT ON COLUMN code_element_embeddings.generated_at IS '임베딩 벡터가 생성된 시각입니다.';


-- 인덱스
-- element_instance_uuid 와 model_name 조합으로 특정 인스턴스의 특정 모델 임베딩을 빠르게 조회
CREATE UNIQUE INDEX uq_idx_code_element_embeddings_instance_model ON code_element_embeddings(element_instance_uuid, embedding_model_name);

-- pgvector 사용 시 벡터 유사도 검색을 위한 HNSW 또는 IVFFlat 인덱스 (예시)
-- 실제 사용할 유사도 측정 방식(L2, inner product, cosine)과 데이터 분포에 따라 인덱스 타입 및 파라미터 결정 필요
-- CREATE INDEX idx_code_element_embeddings_vector_hnsw ON code_element_embeddings USING hnsw (embedding_vector vector_cosine_ops);
-- 참고: 위 HNSW 인덱스 예시는 코사인 유사도 기준입니다.

-- updated_at 컬럼 자동 갱신 트리거 (00_common_functions_and_types.sql 에 set_updated_at 함수 정의 가정)
CREATE TRIGGER trg_set_updated_at_code_element_embeddings
BEFORE UPDATE ON code_element_embeddings
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();