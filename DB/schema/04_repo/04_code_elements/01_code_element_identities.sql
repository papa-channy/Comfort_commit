-- =====================================================================================
-- 파일: 01_code_element_identities.sql
-- 모듈: 04_repo_module / 04_code_elements (함수/클래스 등 코드 요소 단위 정보)
-- 설명: 저장소 내에서 고유하게 식별될 수 있는 코드 요소(함수, 클래스, 인터페이스, 주요 변수 등)의
--       "정체성" 또는 "원형(archetype)"을 정의합니다.
--       이 테이블은 특정 시점의 코드 인스턴스가 아닌, 코드 요소 자체의 고유한 식별 정보를 관리합니다.
--       예를 들어, 파일 위치가 변경되거나 시그니처가 약간 수정되어도 동일한 로직을 수행하는
--       함수/클래스임을 나타낼 수 있는 추상적인 ID를 제공하는 것을 목표로 합니다.
-- 대상 DB: PostgreSQL Primary RDB
-- 파티셔닝: 해당 없음 (코드 요소 정의 마스터 성격)
-- MVP 중점사항: 코드 요소의 고유 ID, 리포지토리 내 고유 경로/이름, 타입(함수/클래스 등), 최초 발견 시점.
-- 스케일업 고려사항: RLS, 코드 요소의 의미론적 해시값(Semantic Hashing) 저장, 버전 관리 개념 도입.
-- =====================================================================================

CREATE TABLE code_element_identities (
    element_identity_uuid UUID PRIMARY KEY DEFAULT gen_random_uuid(), -- 코드 요소 정체성의 고유 식별자 (PK)

    repo_uuid UUID NOT NULL REFERENCES repositories(repo_uuid) ON DELETE CASCADE,
    -- 이 코드 요소가 속한 저장소 (repositories.repo_uuid 참조)

    element_type code_element_type_enum NOT NULL,    -- 코드 요소의 타입 (예: 'FUNCTION', 'CLASS', 'INTERFACE', 'METHOD', 'MODULE_VARIABLE')
                                                      -- (00_repo_enums_and_types.sql 에 정의될 ENUM)

    -- 코드 요소를 고유하게 식별할 수 있는 정보 조합 (리포지토리 내에서 유일해야 함)
    -- 이 조합은 코드 분석 도구나 내부 로직을 통해 결정됩니다.
    -- 예: "파일경로::클래스명::메서드명(시그니처해시)" 또는 "모듈경로::함수명" 등
    -- MVP에서는 단순 이름/경로 기반으로 시작하고, 스케일업 시 시그니처 해시 등 추가 고려
    element_identifier TEXT NOT NULL,
    -- 예시:
    --  - 'src/utils/helpers.py::calculate_sum' (함수)
    --  - 'src/models/user_model.py::User' (클래스)
    --  - 'src/services/auth_service.ts::AuthService::login' (클래스 내 메서드)
    --  - 'config/settings.ini::MAX_RETRIES' (설정 파일 내 주요 변수)

    element_name TEXT NOT NULL,                       -- 코드 요소의 이름 (예: 'calculate_sum', 'User', 'login')
    element_namespace TEXT,                           -- 코드 요소가 속한 네임스페이스 또는 모듈 경로 (선택적, element_identifier 와 중복될 수 있음)
                                                      -- 예: 'src.utils.helpers', 'src.models.user_model'

    -- 코드 요소에 대한 간략한 설명 또는 주석 (파싱 가능할 경우)
    short_description TEXT,

    -- 이 코드 요소 정체성이 시스템에 처음으로 인식된 시점
    first_identified_snapshot_id UUID REFERENCES code_snapshots(snapshot_id) ON DELETE SET NULL,
    -- 최초 발견된 스냅샷 ID (code_snapshots.snapshot_id 참조), 스냅샷 삭제 시 연결만 해제

    -- 이 코드 요소의 "원형"이 처음으로 기록된 시각
    initial_definition_created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- 태그 또는 레이블 (JSONB 형태, 검색 및 분류용)
    tags JSONB DEFAULT '{}'::JSONB,
    -- 예: {"importance": "high", "domain": "authentication", "status": "stable"}

    -- 스케일업 고려:
    -- semantic_hash TEXT UNIQUE, -- 코드 블록의 의미론적 해시값 (내용 기반 유사도 비교용, 매우 높은 유일성 보장 시 UNIQUE)
    -- version_info JSONB,        -- 이 코드 요소의 버전 관리 정보 (별도 테이블로 분리 가능성 높음)

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP

    -- 리포지토리 내에서 element_identifier는 고유해야 함
    CONSTRAINT uq_code_element_identities_repo_identifier UNIQUE (repo_uuid, element_identifier)
);

COMMENT ON TABLE code_element_identities IS '저장소 내에서 고유하게 식별될 수 있는 코드 요소(함수, 클래스 등)의 추상적인 정체성(원형)을 정의합니다.';
COMMENT ON COLUMN code_element_identities.element_identity_uuid IS '코드 요소 정체성의 고유 UUID입니다.';
COMMENT ON COLUMN code_element_identities.repo_uuid IS '이 코드 요소가 속한 저장소의 UUID (repositories.repo_uuid 참조)입니다.';
COMMENT ON COLUMN code_element_identities.element_type IS '코드 요소의 타입을 나타냅니다 (00_repo_enums_and_types.sql에 정의된 code_element_type_enum 값).';
COMMENT ON COLUMN code_element_identities.element_identifier IS '리포지토리 내에서 해당 코드 요소를 고유하게 식별하는 문자열입니다. (예: "파일경로::클래스명::메서드명").';
COMMENT ON COLUMN code_element_identities.element_name IS '코드 요소의 이름입니다 (예: 함수명, 클래스명).';
COMMENT ON COLUMN code_element_identities.element_namespace IS '코드 요소가 속한 네임스페이스 또는 모듈 경로입니다.';
COMMENT ON COLUMN code_element_identities.short_description IS '코드 요소에 대한 간략한 설명 또는 주석에서 추출한 내용입니다.';
COMMENT ON COLUMN code_element_identities.first_identified_snapshot_id IS '이 코드 요소의 정체성이 시스템에 처음으로 인식되었을 때의 스냅샷 ID입니다.';
COMMENT ON COLUMN code_element_identities.initial_definition_created_at IS '이 코드 요소의 "원형" 정의가 처음으로 기록된 시각입니다.';
COMMENT ON COLUMN code_element_identities.tags IS '코드 요소를 분류하거나 검색하기 위한 추가적인 태그 또는 레이블 (JSONB)입니다.';
COMMENT ON CONSTRAINT uq_code_element_identities_repo_identifier ON code_element_identities IS '하나의 저장소 내에서 element_identifier는 고유해야 합니다.';


-- 인덱스
CREATE INDEX idx_code_element_identities_repo_type ON code_element_identities(repo_uuid, element_type);
CREATE INDEX idx_code_element_identities_name ON code_element_identities(element_name); -- 이름으로 검색 시
CREATE INDEX idx_code_element_identities_tags_gin ON code_element_identities USING GIN(tags); -- 태그 검색 시

-- updated_at 컬럼 자동 갱신 트리거 (00_common_functions_and_types.sql 에 set_updated_at 함수 정의 가정)
CREATE TRIGGER trg_set_updated_at_code_element_identities
BEFORE UPDATE ON code_element_identities
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- (00_repo_enums_and_types.sql 에 정의될 ENUM 예시)
-- CREATE TYPE code_element_type_enum AS ENUM (
--     'MODULE',       -- 파일 전체 또는 패키지
--     'NAMESPACE',    -- 네임스페이스 (C++, C# 등)
--     'CLASS',
--     'INTERFACE',
--     'TRAIT',        -- PHP 등
--     'ENUM_TYPE',    -- ENUM 자체 정의
--     'FUNCTION',
--     'METHOD',       -- 클래스 내 함수
--     'CONSTRUCTOR',
--     'DESTRUCTOR',
--     'PROPERTY',     -- 클래스 속성
--     'CONSTANT',     -- 전역 또는 클래스 상수
--     'GLOBAL_VARIABLE',
--     'LOCAL_VARIABLE', -- (범위가 명확하고 중요도가 높을 경우)
--     'TYPE_ALIAS',   -- 타입 별칭 (typedef, using 등)
--     'STRUCT',       -- 구조체
--     'UNION',        -- 공용체
--     'ANNOTATION',   -- 데코레이터, 어노테이션
--     'UNKNOWN'
-- );