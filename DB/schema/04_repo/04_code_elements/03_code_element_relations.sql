-- =====================================================================================
-- 파일: 03_code_element_relations.sql
-- 모듈: 04_repo_module / 04_code_elements (함수/클래스 등 코드 요소 단위 정보)
-- 설명: 특정 스냅샷 시점에서 코드 요소 인스턴스들 간의 관계(예: 호출, 사용, 의존, 상속 등)를 정의합니다.
--       이 정보는 코드 요소 간의 연결성을 파악하고, 변경의 영향을 분석하며,
--       유사도 기반 스코핑의 입력 데이터로 활용될 수 있습니다.
-- 대상 DB: PostgreSQL Primary RDB
-- 파티셔닝: 고려 가능 (snapshot_id 또는 관계 분석 시점 기준으로, 관계 데이터가 매우 많을 경우)
-- MVP 중점사항: 소스-타겟 요소 관계, 관계 타입(ENUM), 분석 방법, (선택적) 관계 강도/확신도.
-- 스케일업 고려사항: RLS, 파티셔닝, 관계의 세부 속성(예: 호출 시 파라미터 정보), 순환 참조 감지 플래그.
-- =====================================================================================

CREATE TABLE code_element_relations (
    relation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(), -- 관계 레코드의 고유 식별자 (PK)

    snapshot_id UUID NOT NULL REFERENCES code_snapshots(snapshot_id) ON DELETE CASCADE,
    -- 이 관계가 분석된 시점의 스냅샷 (code_snapshots.snapshot_id 참조)
    -- 스냅샷이 삭제되면 해당 스냅샷에서 분석된 관계 정보도 함께 삭제

    source_element_instance_uuid UUID NOT NULL REFERENCES snapshot_code_element_instances(element_instance_uuid) ON DELETE CASCADE,
    -- 관계의 출발점이 되는 코드 요소 인스턴스
    -- (snapshot_code_element_instances.element_instance_uuid 참조)

    target_element_instance_uuid UUID NOT NULL REFERENCES snapshot_code_element_instances(element_instance_uuid) ON DELETE CASCADE,
    -- 관계의 대상이 되는 코드 요소 인스턴스
    -- (snapshot_code_element_instances.element_instance_uuid 참조)

    relation_type element_relation_type_enum NOT NULL, -- 관계의 유형 (예: 'CALLS', 'USES_VARIABLE', 'IMPORTS_MODULE', 'INHERITS_FROM', 'IMPLEMENTS_INTERFACE', 'REFERENCES_TYPE')
                                                       -- (00_repo_enums_and_types.sql 에 정의될 ENUM)

    -- 관계가 설정된 구체적인 위치 정보 (선택적, 소스 코드 내)
    source_relation_start_line INT,
    source_relation_end_line INT,
    source_relation_start_column INT,
    source_relation_end_column INT,

    -- 이 관계가 어떻게 분석되었는지에 대한 정보
    analysis_method TEXT,                             -- 예: 'STATIC_IMPORT_ANALYSIS', 'CALL_GRAPH_GENERATION', 'AST_WALK', 'USER_DEFINED'
    confidence_score NUMERIC(5,4),                    -- 이 관계 분석 결과에 대한 확신도 (0.0 ~ 1.0, 선택적)

    -- 관계에 대한 추가적인 메타데이터 (JSONB)
    properties JSONB DEFAULT '{}'::JSONB,
    -- 예: {"call_arguments_count": 3, "is_conditional_call": true, "access_modifier": "public"}
    --     'CALLS' 관계의 경우 호출 시 사용된 파라미터 개수, 조건부 호출 여부 등을 저장 가능

    -- 순환 참조 여부 (선택적, 스케일업 시)
    -- is_circular_dependency BOOLEAN DEFAULT FALSE,

    --  auditing
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- 동일 스냅샷 내에서 소스-타겟-관계타입 조합의 유일성 보장 (분석 방법에 따라 달라질 수 있음)
    CONSTRAINT uq_code_element_relation_snapshot_source_target_type UNIQUE (snapshot_id, source_element_instance_uuid, target_element_instance_uuid, relation_type)
);

COMMENT ON TABLE code_element_relations IS '특정 스냅샷 시점에서 코드 요소 인스턴스들 간의 관계(호출, 의존 등)를 기록합니다.';
COMMENT ON COLUMN code_element_relations.relation_id IS '관계 레코드의 고유 UUID입니다.';
COMMENT ON COLUMN code_element_relations.snapshot_id IS '이 관계가 분석된 시점의 스냅샷 UUID (code_snapshots.snapshot_id 참조)입니다.';
COMMENT ON COLUMN code_element_relations.source_element_instance_uuid IS '관계의 시작점(호출하는 쪽, 의존하는 쪽 등)이 되는 코드 요소 인스턴스의 UUID입니다.';
COMMENT ON COLUMN code_element_relations.target_element_instance_uuid IS '관계의 대상(호출되는 쪽, 의존되는 쪽 등)이 되는 코드 요소 인스턴스의 UUID입니다.';
COMMENT ON COLUMN code_element_relations.relation_type IS '코드 요소 간의 관계 유형을 나타냅니다 (00_repo_enums_and_types.sql에 정의된 element_relation_type_enum 값).';
COMMENT ON COLUMN code_element_relations.source_relation_start_line IS '소스 코드 요소 내에서 이 관계가 시작되는 라인 번호입니다 (선택적).';
COMMENT ON COLUMN code_element_relations.source_relation_end_line IS '소스 코드 요소 내에서 이 관계가 끝나는 라인 번호입니다 (선택적).';
COMMENT ON COLUMN code_element_relations.analysis_method IS '이 관계를 분석하거나 식별하는 데 사용된 방법 또는 도구의 이름입니다.';
COMMENT ON COLUMN code_element_relations.confidence_score IS '분석된 관계의 정확성에 대한 확신도 점수입니다 (0.0 ~ 1.0).';
COMMENT ON COLUMN code_element_relations.properties IS '관계에 대한 추가적인 속성 정보를 JSONB 형태로 저장합니다 (예: 호출 인자 정보).';
COMMENT ON CONSTRAINT uq_code_element_relation_snapshot_source_target_type ON code_element_relations IS '동일 스냅샷 내에서 두 코드 요소 인스턴스 간에 동일한 타입의 관계는 유일해야 합니다.';


-- 인덱스
CREATE INDEX idx_code_element_relations_snapshot_source ON code_element_relations(snapshot_id, source_element_instance_uuid);
CREATE INDEX idx_code_element_relations_snapshot_target ON code_element_relations(snapshot_id, target_element_instance_uuid);
CREATE INDEX idx_code_element_relations_relation_type ON code_element_relations(relation_type);
CREATE INDEX idx_code_element_relations_analysis_method ON code_element_relations(analysis_method);

-- 복합 인덱스 (특정 요소의 모든 관계 조회 시 유용)
CREATE INDEX idx_code_element_relations_source_or_target ON code_element_relations USING GIN (ARRAY[source_element_instance_uuid, target_element_instance_uuid]);


-- updated_at 컬럼 자동 갱신 트리거 (00_common_functions_and_types.sql 에 set_updated_at 함수 정의 가정)
CREATE TRIGGER trg_set_updated_at_code_element_relations
BEFORE UPDATE ON code_element_relations
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- (00_repo_enums_and_types.sql 에 정의될 ENUM 예시)
-- CREATE TYPE element_relation_type_enum AS ENUM (
--     'CALLS',                        -- 함수/메서드 호출
--     'USES_VARIABLE',                -- 변수 사용 (읽기/쓰기)
--     'DEFINES_VARIABLE',             -- 변수 정의
--     'IMPORTS_MODULE',               -- 모듈/파일 임포트
--     'EXPORTS_ELEMENT',              -- 요소 외부 노출 (export)
--     'INHERITS_FROM',                -- 클래스 상속
--     'IMPLEMENTS_INTERFACE',         -- 인터페이스 구현
--     'REFERENCES_TYPE',              -- 특정 타입 참조 (파라미터, 반환형, 변수 선언 등)
--     'CREATES_INSTANCE_OF',          -- 객체 인스턴스 생성
--     'THROWS_EXCEPTION',             -- 예외 발생
--     'CATCHES_EXCEPTION',            -- 예외 처리
--     'ANNOTATED_BY',                 -- 어노테이션/데코레이터에 의해 수식됨
--     'ANNOTATES',                    -- 다른 요소를 수식하는 어노테이션/데코레이터
--     'DEPENDS_ON_FILE',              -- 파일 수준의 의존성
--     'RELATED_TO_SEMANTIC',          -- (임베딩 등) 의미론적으로 관련된 경우 (직접적 코드 연결은 없을 수 있음)
--     'CUSTOM_USER_DEFINED'           -- 사용자가 직접 정의한 관계
-- );