-- =====================================================================================
-- 파일: 02_snapshot_code_element_instances.sql
-- 모듈: 04_repo_module / 04_code_elements (함수/클래스 등 코드 요소 단위 정보)
-- 설명: 'code_element_identities'에서 정의된 코드 요소의 "정체성"이 특정 스냅샷 시점에서
--       어떤 실제 내용과 속성(예: 라인 수, 실제 코드 조각, 시그니처 등)을 가지고 있는지를 기록합니다.
--       이 테이블의 레코드는 LLM 호출 시 분석 대상이 되는 구체적인 코드 요소의 "실체"입니다.
-- 대상 DB: PostgreSQL Primary RDB
-- 파티셔닝: 고려 가능 (snapshot_id 기준으로, 매우 많은 스냅샷과 코드 요소 인스턴스가 발생할 경우)
-- MVP 중점사항: 코드 요소 정체성 참조, 스냅샷 파일 참조, 라인 정보, 이름/시그니처, (선택적) 짧은 코드 조각.
-- 스케일업 고려사항: RLS, 파티셔닝, 전체 코드 내용 외부 저장소 참조, AST 파싱 결과 요약 저장.
-- =====================================================================================

CREATE TABLE snapshot_code_element_instances (
    element_instance_uuid UUID PRIMARY KEY DEFAULT gen_random_uuid(), -- 코드 요소 인스턴스의 고유 식별자 (PK)

    element_identity_uuid UUID NOT NULL REFERENCES code_element_identities(element_identity_uuid) ON DELETE CASCADE,
    -- 이 인스턴스가 어떤 코드 요소 "정체성"에 해당하는지 참조 (code_element_identities.element_identity_uuid)
    -- ON DELETE CASCADE: 코드 요소의 정체성(원형)이 삭제되면, 해당 정체성을 가지는 모든 시점의 인스턴스도 함께 삭제

    snapshot_file_id UUID NOT NULL REFERENCES snapshot_file_instances(snapshot_file_id) ON DELETE CASCADE,
    -- 이 코드 요소 인스턴스가 포함된 특정 스냅샷의 파일 인스턴스 (snapshot_file_instances.snapshot_file_id 참조)
    -- ON DELETE CASCADE: 해당 파일 인스턴스가 스냅샷에서 사라지면, 그 안의 코드 요소 인스턴스도 함께 삭제

    -- 해당 스냅샷 파일 내에서 이 코드 요소의 위치 정보
    start_line_number INT NOT NULL,
    end_line_number INT NOT NULL,
    start_column_number INT, -- 선택적 (보다 정밀한 위치 정보가 필요할 경우)
    end_column_number INT,   -- 선택적

    -- 해당 스냅샷 시점에서의 코드 요소 이름 및 시그니처 (정체성의 이름과 다를 수 있음 - 예: 리팩토링 중)
    instance_name TEXT NOT NULL,            -- 예: 'calculate_total_price', 'UserModel'
    instance_signature TEXT,                -- 함수/메서드의 경우 파라미터 및 반환 타입 포함한 시그니처
                                            -- 예: '(items: List[Item], discount_rate: float) -> float'
                                            -- 클래스의 경우 주요 속성이나 생성자 정보 요약 가능

    -- 실제 코드 내용 (LLM 입력으로 직접 활용될 수 있음)
    code_content_snippet TEXT,              -- 짧은 코드 요소의 경우 전체 내용을 저장하거나, 긴 경우 핵심 요약/일부만 저장.
                                            -- (PII 및 저장 공간, 성능 고려. 매우 긴 코드는 외부 참조 고려)
    -- full_code_content_external_ref TEXT, -- (스케일업) 전체 코드 내용이 매우 길 경우 외부 저장소(S3, Git LFS 등) 참조 ID

    -- 이 인스턴스에 대한 추가 메타데이터 (JSONB)
    metadata JSONB DEFAULT '{}'::JSONB,
    -- 예: {"cyclomatic_complexity": 5, "is_deprecated": false, "visibility": "public", "dependencies": ["module_a", "module_b"]}
    --    file_analysis_metrics 테이블의 일부 요약 정보나, AST 파싱 결과의 주요 특징을 저장할 수 있음.

    -- 이 인스턴스가 이전 스냅샷의 어떤 인스턴스와 연관되는지 (코드 추적용, 선택적)
    -- previous_element_instance_uuid UUID REFERENCES snapshot_code_element_instances(element_instance_uuid) ON DELETE SET NULL,

    --  auditing
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, -- 내용보다는 메타데이터 변경 시 업데이트

    -- 특정 스냅샷 파일 내에서 동일한 코드 요소 정체성이 중복으로 존재하지 않도록 보장 (일반적으로는 발생하지 않으나, 방어적 설계)
    -- 다만, 동일 파일 내에 동일 이름의 오버로딩된 함수/메서드가 존재할 경우 element_identity_uuid가 달라야 함.
    -- 이 제약은 element_identity_uuid가 "파일 내 상대적 위치+시그니처" 등으로 충분히 유일하게 생성된다는 전제가 필요.
    CONSTRAINT uq_snapshot_element_identity UNIQUE (snapshot_file_id, element_identity_uuid)
);

COMMENT ON TABLE snapshot_code_element_instances IS '특정 스냅샷 시점에서 존재하는 각 코드 요소(함수, 클래스 등)의 실제 내용과 속성을 기록합니다.';
COMMENT ON COLUMN snapshot_code_element_instances.element_instance_uuid IS '코드 요소 인스턴스의 고유 UUID입니다.';
COMMENT ON COLUMN snapshot_code_element_instances.element_identity_uuid IS '이 인스턴스가 참조하는 코드 요소의 "정체성" UUID (code_element_identities.element_identity_uuid)입니다.';
COMMENT ON COLUMN snapshot_code_element_instances.snapshot_file_id IS '이 코드 요소 인스턴스가 속한 스냅샷 내 파일 인스턴스의 UUID (snapshot_file_instances.snapshot_file_id)입니다.';
COMMENT ON COLUMN snapshot_code_element_instances.start_line_number IS '해당 스냅샷 파일 내에서 코드 요소가 시작하는 라인 번호입니다.';
COMMENT ON COLUMN snapshot_code_element_instances.end_line_number IS '해당 스냅샷 파일 내에서 코드 요소가 끝나는 라인 번호입니다.';
COMMENT ON COLUMN snapshot_code_element_instances.instance_name IS '해당 스냅샷 시점에서의 코드 요소 이름입니다 (리팩토링 등으로 정체성의 이름과 다를 수 있습니다).';
COMMENT ON COLUMN snapshot_code_element_instances.instance_signature IS '함수/메서드의 경우, 해당 스냅샷 시점에서의 파라미터 및 반환 타입 등을 포함한 시그니처입니다.';
COMMENT ON COLUMN snapshot_code_element_instances.code_content_snippet IS '실제 코드 내용의 일부 또는 전체입니다. LLM 입력으로 활용될 수 있으며, 매우 긴 경우 요약되거나 외부 참조될 수 있습니다.';
COMMENT ON COLUMN snapshot_code_element_instances.metadata IS '이 코드 요소 인스턴스에 대한 추가적인 메타데이터 (예: 정적 분석 결과 요약, 가시성 등)를 JSONB 형태로 저장합니다.';
COMMENT ON CONSTRAINT uq_snapshot_element_identity ON snapshot_code_element_instances IS '하나의 스냅샷 파일 내에서 동일한 코드 요소 정체성(element_identity_uuid)을 가진 인스턴스는 유일해야 합니다.';


-- 인덱스
CREATE INDEX idx_snapshot_code_element_instances_identity_snapshot ON snapshot_code_element_instances(element_identity_uuid, snapshot_file_id);
CREATE INDEX idx_snapshot_code_element_instances_snapshot_file_id ON snapshot_code_element_instances(snapshot_file_id);
CREATE INDEX idx_snapshot_code_element_instances_instance_name ON snapshot_code_element_instances(instance_name); -- 이름으로 검색 시

-- updated_at 컬럼 자동 갱신 트리거 (00_common_functions_and_types.sql 에 set_updated_at 함수 정의 가정)
CREATE TRIGGER trg_set_updated_at_snapshot_code_element_instances
BEFORE UPDATE ON snapshot_code_element_instances
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();