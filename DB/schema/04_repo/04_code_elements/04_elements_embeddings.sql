-- =====================================================================================
-- 파일: 04_code_element_embeddings.sql
-- 모듈: 04_repo_module / 04_code_elements (함수/클래스 등 코드 요소 단위 정보)
-- 설명: 특정 스냅샷 시점의 코드 요소 인스턴스에 대해 계산된 임베딩 벡터와,
--       다른 코드 요소 인스턴스와의 계산된 유사도 점수를 저장합니다.
--       (예: Code2Vec, AST 기반 임베딩, Sentence-BERT 등 다양한 모델 활용 가능)
--       이 정보는 의미론적 유사도 기반 스코핑 및 관련 코드 추천 등에 활용됩니다.
-- 대상 DB: PostgreSQL Primary RDB (pgvector 확장 필요)
-- 파티셔닝: 고려 가능 (element_instance_id 또는 embedding_model_name 기준으로, 데이터가 매우 많을 경우)
-- MVP 중점사항: 코드 요소 인스턴스 참조, 임베딩 모델 정보, 벡터 값, 버전 관리.
-- 스케일업 고려사항: RLS, 파티셔닝, 다양한 임베딩 모델 지원, 근사 최근접 이웃(ANN) 검색 최적화.
-- =====================================================================================

-- pgvector 확장이 설치되어 있어야 `vector` 타입을 사용할 수 있습니다.
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE code_element_embeddings (
    embedding_uuid id PRIMARY KEY DEFAULT gen_random_id(), -- 임베딩 레코드의 고유 식별자 (PK)

    element_instance_id id NOT NULL REFERENCES snapshot_code_element_instances(element_instance_id) ON DELETE CASCADE,
    -- 이 임베딩이 계산된 대상 코드 요소 인스턴스
    -- (snapshot_code_element_instances.element_instance_id 참조)

    embedding_model_name TEXT NOT NULL,        -- 사용된 임베딩 모델의 이름 (예: 'code2vec_cbow', 'sentence-bert-base-nli-mean-tokens', 'text-embedding-ada-002')
    embedding_model_version TEXT,              -- 사용된 임베딩 모델의 버전 (선택적)
    vector_dimensions INT NOT NULL,            -- 임베딩 벡터의 차원 수 (예: 128, 768, 1536)

    current_embedding_vector VECTOR(1536),     -- 🔄 최신 벡터만 저장 (pgvector 타입, 차원 수는 사용하는 모델 중 최대값 또는 대표값으로 설정)
    current_version TEXT NOT NULL,             -- 🆕 현재 저장된 벡터의 버전 (예: 'v2024-06-01', 'model_xyz_v1.2')

    -- 임베딩 계산에 사용된 소스 코드의 해시값 (내용 변경 시 재계산 여부 판단용, 선택적)
    source_code_checksum TEXT,

    --  auditing
    generated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, -- 최신 임베딩이 생성/업데이트된 시각
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,   -- 이 레코드가 처음 생성된 시각
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP    -- 이 레코드 정보가 마지막으로 수정된 시각
);

COMMENT ON TABLE code_element_embeddings IS '특정 스냅샷 시점의 코드 요소 인스턴스에 대한 "최신" 임베딩 벡터 및 관련 정보를 저장합니다.';
COMMENT ON COLUMN code_element_embeddings.embedding_uuid IS '임베딩 레코드의 고유 id입니다.';
COMMENT ON COLUMN code_element_embeddings.element_instance_id IS '임베딩이 계산된 코드 요소 인스턴스의 id입니다.';
COMMENT ON COLUMN code_element_embeddings.embedding_model_name IS '임베딩 생성에 사용된 모델의 이름입니다.';
COMMENT ON COLUMN code_element_embeddings.embedding_model_version IS '사용된 임베딩 모델의 버전입니다.';
COMMENT ON COLUMN code_element_embeddings.vector_dimensions IS '임베딩 벡터의 차원 수입니다.';
COMMENT ON COLUMN code_element_embeddings.current_embedding_vector IS '🔄 현재 유효한 최신 임베딩 벡터 값입니다 (pgvector 타입).';
COMMENT ON COLUMN code_element_embeddings.current_version IS '🆕 현재 저장된 `current_embedding_vector`의 버전 태그 또는 식별자입니다.';
COMMENT ON COLUMN code_element_embeddings.source_code_checksum IS '임베딩 계산의 기반이 된 소스 코드의 체크섬입니다 (선택적).';
COMMENT ON COLUMN code_element_embeddings.generated_at IS '현재 `current_embedding_vector`가 생성되거나 업데이트된 시각입니다.';
COMMENT ON COLUMN code_element_embeddings.created_at IS '이 임베딩 정보 레코드가 데이터베이스에 처음 생성된 시각입니다.';
COMMENT ON COLUMN code_element_embeddings.updated_at IS '이 임베딩 정보 레코드가 마지막으로 수정된 시각입니다.';


-- 인덱스
CREATE UNIQUE INDEX uq_uuidx_code_element_embeddings_instance_model ON code_element_embeddings(element_instance_id, embedding_model_name);
-- pgvector 사용 시 벡터 유사도 검색을 위한 HNSW 또는 IVFFlat 인덱스 (예시)
-- CREATE INDEX uuidx_cee_current_vector_hnsw ON code_element_embeddings USING hnsw (current_embedding_vector vector_cosine_ops);

-- updated_at 컬럼 자동 갱신 트리거
CREATE TRIGGER trg_set_updated_at_code_element_embeddings
BEFORE UPDATE ON code_element_embeddings
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =====================================================================================
-- [🆕 추가 테이블] 코드 요소 임베딩 버전별 누적 저장 테이블
-- 설명: 모든 이전 임베딩 결과를 버전별로 누적 저장하며, 시계열 분석 및 리팩토링 패턴 추출에 활용됩니다.
--       실제 분석은 이 테이블을 기준으로 진행하고, 최신 결과만 code_element_embeddings에 유지됩니다.
-- =====================================================================================

CREATE TABLE code_element_embedding_versions (
    version_embedding_uuid id PRIMARY KEY DEFAULT gen_random_id(), -- 🆕 각 버전 저장 row의 고유 식별자 (embedding_uuid 대신 version_embedding_uuid 사용)
    element_instance_id id NOT NULL REFERENCES snapshot_code_element_instances(element_instance_id) ON DELETE CASCADE,
    embedding_model_name TEXT NOT NULL,
    embedding_model_version TEXT,
    embedding_version_tag TEXT NOT NULL,           -- 🆕 임베딩의 버전 (날짜 버전 또는 수동 버전, 기존 version 컬럼명 변경)
    vector_dimensions INT NOT NULL,
    embedding_vector VECTOR(1536) NOT NULL,        -- 🆕 해당 버전의 임베딩 벡터 (차원 수 명시)
    source_code_checksum TEXT,
    generated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, -- 🆕 이 임베딩 버전이 생성된 시간
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP   -- 이 버전 레코드가 DB에 생성된 시간
);

COMMENT ON TABLE code_element_embedding_versions IS '🆕 코드 요소 인스턴스에 대한 임베딩 결과를 버전별로 누적 저장하는 테이블입니다. 시계열 분석 등에 활용될 수 있습니다.';
COMMENT ON COLUMN code_element_embedding_versions.version_embedding_uuid IS '임베딩 버전 레코드의 고유 id입니다.';
COMMENT ON COLUMN code_element_embedding_versions.element_instance_id IS '임베딩이 계산된 코드 요소 인스턴스의 id입니다.';
COMMENT ON COLUMN code_element_embedding_versions.embedding_model_name IS '임베딩 생성에 사용된 모델의 이름입니다.';
COMMENT ON COLUMN code_element_embedding_versions.embedding_model_version IS '사용된 임베딩 모델의 버전입니다.';
COMMENT ON COLUMN code_element_embedding_versions.embedding_version_tag IS '🆕 이 임베딩 벡터의 버전을 나타내는 태그 또는 식별자입니다 (예: YYYYMMDDHHMMSS, 모델 체크포인트 uuid).';
COMMENT ON COLUMN code_element_embedding_versions.vector_dimensions IS '임베딩 벡터의 차원 수입니다.';
COMMENT ON COLUMN code_element_embedding_versions.embedding_vector IS '🆕 해당 버전에서 계산된 실제 임베딩 벡터 값입니다 (pgvector 타입).';
COMMENT ON COLUMN code_element_embedding_versions.source_code_checksum IS '임베딩 계산의 기반이 된 소스 코드의 체크섬입니다 (선택적).';
COMMENT ON COLUMN code_element_embedding_versions.generated_at IS '🆕 이 임베딩 버전이 생성된 시간입니다.';
COMMENT ON COLUMN code_element_embedding_versions.created_at IS '이 임베딩 버전 레코드가 데이터베이스에 처음 생성된 시각입니다.';

CREATE INDEX uuidx_ceev_instance_model_version ON code_element_embedding_versions (element_instance_id, embedding_model_name, embedding_version_tag);
CREATE INDEX uuidx_ceev_generated_at ON code_element_embedding_versions (generated_at DESC);
-- pgvector 사용 시 벡터 유사도 검색을 위한 HNSW 또는 IVFFlat 인덱스 (예시)
-- CREATE INDEX uuidx_ceev_vector_hnsw ON code_element_embedding_versions USING hnsw (embedding_vector vector_cosine_ops);