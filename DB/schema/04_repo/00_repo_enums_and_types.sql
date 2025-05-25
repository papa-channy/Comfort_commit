-- =====================================================================================
-- 파일: 00_repo_enums_and_types.sql
-- 모듈: 04_repo_module (레포지토리 및 커밋 흐름 전체)
-- 설명: '04_repo_module' 내의 여러 테이블에서 공통적으로 사용되는 ENUM 타입 및
--       사용자 정의 복합 타입을 정의합니다.
--       이를 통해 데이터의 일관성을 유지하고, 코드 가독성을 높이며,
--       유효한 값의 범위를 제한하여 데이터 무결성을 강화합니다.
-- 대상 DB: PostgreSQL Primary RDB
-- =====================================================================================

-- DROP TYPE IF EXISTS ... CASCADE; -- 개발 중 ENUM 변경 시 기존 타입 삭제 필요할 수 있음 (주의해서 사용)

-- =====================================================================================
-- 1. `02_code_snapshots` 관련 ENUM 및 타입
-- =====================================================================================

-- `03_file_diff_fragments.sql` 에서 사용
CREATE TYPE diff_change_type_enum AS ENUM (
    'ADDED',       -- 파일 또는 코드 조각 추가
    'MODIFIED',    -- 파일 또는 코드 조각 내용 수정
    'DELETED',     -- 파일 또는 코드 조각 삭제
    'RENAMED',     -- 파일 이름 변경 (내용 변경도 포함될 수 있음)
    'COPIED',      -- 파일 복사
    'TYPE_CHANGED' -- 파일 타입 변경 (예: 심볼릭 링크 -> 파일)
);
COMMENT ON TYPE diff_change_type_enum IS '파일 또는 코드 조각의 변경 유형을 나타내는 ENUM 타입입니다.';


-- =====================================================================================
-- 2. `03_files` 관련 ENUM 및 타입
-- =====================================================================================

-- `03_file_analysis_metrics.sql` 에서 사용 (프로그래머 작업 흐름도 정보 중심)
CREATE TYPE metric_type_enum AS ENUM (
    -- 기본 파일 통계
    'LINES_OF_CODE_TOTAL',          -- 전체 라인 수
    'LINES_OF_CODE_CODE',           -- 실제 코드 라인 수 (주석, 공백 제외)
    'LINES_OF_CODE_COMMENT',        -- 주석 라인 수
    'COMMENT_RATIO',                -- 주석 비율 (COMMENT / TOTAL)
    'FILE_SIZE_BYTES',              -- 파일 크기 (바이트)
    'LANGUAGE_IDENTIFIED',          -- 식별된 프로그래밍 언어 (예: 'Python', 'JavaScript')

    -- 변경 이력 및 활동성 관련
    'RECENT_CHANGE_INTENSITY_SCORE',-- 최근 변경 강도 점수 (예: 최근 N일간 변경된 라인 수, 커밋 빈도 등 종합)
    'FILE_AGE_DAYS',                -- 파일 생성 후 경과 일수
    'LAST_COMMIT_TIMESTAMP_OF_FILE',-- 이 파일이 마지막으로 변경된 커밋의 타임스탬프
    'LAST_MODIFIED_BY_AUTHOR',      -- 마지막 수정자 (git blame 정보 활용)
    'NUMBER_OF_AUTHORS',            -- 이 파일을 수정한 총 저자 수
    'OWNERSHIP_PERCENTAGE_TOP_DEV', -- 주요 기여자(Top1)의 코드 소유권 비율 (git blame 기반)

    -- 의존성 및 구조 관련
    'DEPENDENCY_COUNT_INTERNAL',    -- 내부 모듈(파일) 의존성 개수
    'DEPENDENCY_COUNT_EXTERNAL',    -- 외부 라이브러리 의존성 개수
    'IMPORTED_MODULE_LIST_JSON',    -- import된 모듈 목록 (JSONB 값과 연동, 여기서는 타입만 명시)
    'EXPORTED_ELEMENT_COUNT',       -- 외부로 노출되는 함수/클래스 등의 개수
    'FUNCTION_COUNT_IN_FILE',       -- 파일 내 최상위 함수 개수
    'CLASS_COUNT_IN_FILE',          -- 파일 내 최상위 클래스 개수
    'COMPLEXITY_CYCLOMATIC_AVG',    -- 파일 내 함수/메서드의 평균 순환 복잡도
    'COMPLEXITY_HALSTEAD_VOLUME',   -- Halstead 볼륨 (파일 전체 또는 주요 부분)

    -- LLM 및 Comfort Commit 특화 정보
    'LLM_CONTEXT_RELEVANCE_SCORE',  -- LLM 입력 컨텍스트로서의 관련도 점수 (내부 로직)
    'NEEDS_TECH_DESCRIPTION_FLAG',  -- 이 파일/요소에 대한 기술 설명서 생성 필요 여부 플래그
    'POTENTIAL_REFACTORING_CANDIDATE_SCORE', -- 리팩토링 후보로서의 잠재력 점수

    -- 보안 및 품질 (일반적인 정적 분석 도구 항목, 필요시 활성화)
    -- 'SECURITY_VULNERABILITY_COUNT_CRITICAL',
    -- 'SECURITY_VULNERABILITY_COUNT_HIGH',
    -- 'LINTER_ERRORS_COUNT',
    -- 'LINTER_WARNINGS_COUNT',
    -- 'CODE_SMELL_COUNT_MAJOR',
    -- 'DUPLICATION_PERCENTAGE_FILE',

    'OTHER_CUSTOM_METRIC'           -- 기타 사용자 정의 메트릭
);
COMMENT ON TYPE metric_type_enum IS '파일 메타정보 또는 분석된 메트릭의 종류를 나타내는 ENUM 타입입니다.';


-- =====================================================================================
-- 3. `04_code_elements` 관련 ENUM 및 타입
-- =====================================================================================

-- `01_code_element_identities.sql` 및 `02_snapshot_code_element_instances.sql` 에서 사용
CREATE TYPE code_element_type_enum AS ENUM (
    'MODULE',               -- 파일 전체 또는 패키지/디렉토리 단위
    'NAMESPACE',            -- 네임스페이스 (C++, C#, Python __init__.py 등)
    'CLASS',                -- 클래스 정의
    'INTERFACE',            -- 인터페이스 정의
    'TRAIT',                -- 트레이트 (PHP, Rust 등)
    'ENUM_TYPE',            -- ENUM 자체의 정의
    'ENUM_MEMBER',          -- ENUM 내부의 각 멤버
    'FUNCTION',             -- 전역 또는 모듈 레벨 함수
    'METHOD',               -- 클래스 또는 객체 내의 메서드
    'CONSTRUCTOR',          -- 생성자 메서드
    'DESTRUCTOR',           -- 소멸자 메서드 (C++ 등)
    'GETTER',               -- Getter 메서드
    'SETTER',               -- Setter 메서드
    'PROPERTY',             -- 클래스 속성 (멤버 변수)
    'CONSTANT',             -- 전역 또는 클래스 레벨 상수
    'GLOBAL_VARIABLE',      -- 전역 변수
    'LOCAL_VARIABLE',       -- 함수/메서드 내 지역 변수 (스코핑 대상이 될 만큼 중요하다면)
    'TYPE_ALIAS',           -- 타입 별칭 (typedef, using, type 등)
    'STRUCT',               -- 구조체 정의
    'UNION',                -- 공용체 정의
    'ANNOTATION_OR_DECORATOR',-- 어노테이션 또는 데코레이터 자체의 정의
    'PARAMETER',            -- 함수/메서드의 파라미터
    'RETURN_TYPE',          -- 함수/메서드의 반환 타입
    'IMPORT_STATEMENT',
    'EXPORT_STATEMENT',
    'CODE_BLOCK',           -- 특정 로직을 수행하는 일반 코드 블록 (예: if, for, try-catch)
    'COMMENT_BLOCK',        -- 중요한 주석 블록
    'UNKNOWN_ELEMENT'       -- 분류되지 않거나 알 수 없는 코드 요소
);
COMMENT ON TYPE code_element_type_enum IS '코드 요소의 타입을 나타내는 ENUM 타입입니다 (함수, 클래스, 모듈 등).';

-- `03_code_element_relations.sql` 에서 사용
CREATE TYPE element_relation_type_enum AS ENUM (
    -- 호출 및 실행 흐름
    'CALLS_FUNCTION',           -- 다른 함수/메서드를 직접 호출
    'CALLS_METHOD',             -- 객체의 메서드를 호출
    'CREATES_INSTANCE_OF',      -- 특정 클래스의 인스턴스를 생성 (new 키워드 등)
    'REFERENCES_FUNCTION_POINTER',-- 함수 포인터 또는 델리게이트 참조
    'THROWS_EXCEPTION',         -- 특정 타입의 예외를 발생시킴
    'CATCHES_EXCEPTION',        -- 특정 타입의 예외를 처리함
    'HAS_CONTROL_FLOW_TO',      -- 제어 흐름이 이어짐 (예: goto, continuos-passing style)

    -- 데이터 사용 및 의존성
    'USES_VARIABLE',            -- 변수(멤버, 전역, 지역)를 읽거나 사용
    'MODIFIES_VARIABLE',        -- 변수(멤버, 전역, 지역)의 값을 수정
    'DEFINES_VARIABLE_OR_PROPERTY',-- 변수 또는 속성을 정의
    'ACCESSES_FIELD_OR_PROPERTY',-- 객체의 필드나 속성에 접근
    'RETURNS_VALUE_OF_TYPE',    -- 특정 타입의 값을 반환

    -- 모듈 및 타입 시스템 관련
    'IMPORTS_MODULE_OR_FILE',   -- 다른 모듈이나 파일을 임포트
    'EXPORTS_ELEMENT',          -- 함수, 클래스 등을 외부로 노출 (export)
    'INHERITS_FROM_CLASS',      -- 다른 클래스를 상속
    'IMPLEMENTS_INTERFACE',     -- 특정 인터페이스를 구현
    'EXTENDS_CLASS_OR_INTERFACE',-- 클래스 또는 인터페이스를 확장 (Java `extends`, TypeScript 등)
    'REFERENCES_TYPE',          -- 특정 타입을 참조 (파라미터 타입, 변수 선언, 반환 타입 등)
    'IS_INSTANCE_OF_CLASS',     -- 특정 클래스의 인스턴스임 (타입 검사)
    'HAS_PARAMETER_OF_TYPE',    -- 특정 타입을 파라미터로 가짐
    'USES_GENERIC_TYPE',        -- 제네릭 타입을 사용

    -- 어노테이션/데코레이터 관련
    'ANNOTATED_BY_OR_DECORATED_BY',-- 특정 어노테이션/데코레이터에 의해 수식됨
    'ANNOTATES_OR_DECORATES',   -- 다른 코드 요소를 수식하는 어노테이션/데코레이터

    -- 파일 및 시스템 수준 의존성
    'DEPENDS_ON_FILE',          -- 특정 파일에 대한 의존성 (컴파일 의존성 등)
    'INCLUDES_HEADER',          -- (C/C++) 헤더 파일을 인클루드

    -- 의미론적 또는 추상적 관계
    'RELATED_TO_SEMANTICALLY',  -- (임베딩 등 분석 결과) 의미론적으로 관련된 경우 (직접적 코드 연결은 없을 수 있음)
    'PART_OF_FEATURE',          -- 특정 기능(feature)의 일부임 (사용자 정의 또는 태깅 기반)
    'ADDRESSES_REQUIREMENT',    -- 특정 요구사항을 만족시킴 (외부 시스템 연동 가능)

    'CUSTOM_USER_DEFINED_RELATION'-- 사용자가 직접 정의한 커스텀 관계
);
COMMENT ON TYPE element_relation_type_enum IS '코드 요소들 간의 관계 유형을 나타내는 ENUM 타입입니다.';


-- =====================================================================================
-- 4. `05_commit_generation` 관련 ENUM 및 타입
-- =====================================================================================

-- `01_commit_generation_requests.sql` 에서 사용
CREATE TYPE request_status_enum AS ENUM (
    'PENDING',                      -- 요청 접수, 처리 대기 중
    'PREPROCESSING_FILES',          -- 파일 정보 수집 및 기본 분석 중
    'SCOPING_INITIAL_CANDIDATES',   -- 초기 스코핑 후보군 생성 중
    'SCOPING_STATIC_ANALYSIS',      -- 정적 분석 기반 스코핑 진행 중
    'SCOPING_EMBEDDING_ANALYSIS',   -- 임베딩 기반 스코핑 진행 중
    'SCOPING_COMPLETED',            -- 스코핑 완료, 1차 LLM(기술 설명서 생성) 대기
    'GENERATING_TECH_DESCRIPTION',  -- 1차 LLM 호출: 기술 설명서 생성 중
    'TECH_DESCRIPTION_READY',       -- 기술 설명서 생성 완료, 2차 LLM(커밋 메시지 생성) 대기
    'GENERATING_COMMIT_MESSAGE',    -- 2차 LLM 호출: 커밋 메시지 생성 중
    'COMMIT_MESSAGE_READY',         -- 커밋 메시지 초안 생성 완료, 사용자 검토 대기
    'AWAITING_USER_REVIEW',         -- 사용자 검토 대기 중 (웹/모바일 인터페이스)
    'USER_APPROVED_AS_IS',          -- 사용자가 LLM 초안 그대로 승인함
    'USER_EDITED_AND_APPROVED',     -- 사용자가 LLM 초안 수정 후 승인함
    'AUTO_COMMITTED_BY_RULE',       -- (정책에 따라) 시스템이 자동 커밋함
    'COMPLETED_SUCCESSFULLY',       -- 모든 처리 성공적으로 완료 (Git 커밋/푸시 포함 또는 미포함)
    'FAILED_PREPROCESSING',         -- 전처리 단계 실패
    'FAILED_SCOPING',               -- 스코핑 단계 실패
    'FAILED_LLM_TECH_DESCRIPTION',  -- 1차 LLM(기술 설명서 생성) 호출 실패
    'FAILED_LLM_COMMIT_MESSAGE',    -- 2차 LLM(커밋 메시지 생성) 호출 실패
    'FAILED_GIT_COMMIT_ACTION',     -- 실제 Git 커밋 실행 실패
    'FAILED_GIT_PUSH_ACTION',       -- 실제 Git 푸시 실행 실패
    'CANCELLED_BY_USER',            -- 사용자에 의해 요청 취소됨
    'TIMED_OUT_PROCESSING',         -- 처리 시간 초과
    'UNKNOWN_ERROR'                 -- 알 수 없는 오류로 실패
);
COMMENT ON TYPE request_status_enum IS '커밋 생성 요청의 처리 상태를 나타내는 ENUM 타입입니다.';

-- `03_finalized_commits.sql` 에서 사용
CREATE TYPE push_status_enum AS ENUM (
    'NOT_APPLICABLE',   -- Push 작업이 해당되지 않음 (예: 로컬 커밋만)
    'NOT_PUSHED',       -- 아직 Push 되지 않음
    'PUSH_PENDING',     -- Push 대기열에 있음 또는 진행 예정
    'PUSH_IN_PROGRESS', -- Push 진행 중
    'PUSH_SUCCESSFUL',  -- Push 성공
    'PUSH_FAILED',      -- Push 실패
    'PUSH_PARTIAL'      -- 부분적으로 Push 성공 (일부 브랜치/태그 등)
);
COMMENT ON TYPE push_status_enum IS 'Git Push 작업의 상태를 나타내는 ENUM 타입입니다.';

-- `06_llm_input_context_details.sql` 에서 사용
CREATE TYPE llm_call_stage_enum AS ENUM (
    'TECHNICAL_DESCRIPTION_GENERATION', -- 1차 LLM 호출 (코드 요소 기술 설명서 생성)
    'COMMIT_MESSAGE_GENERATION',      -- 2차 LLM 호출 (커밋 메시지 초안 생성)
    'CODE_ANALYSIS_SUMMARY',        -- (향후 확장) 코드 변경 전반에 대한 요약 생성
    'CODE_REFACTORING_SUGGESTION',  -- (향후 확장) 리팩토링 아이디어 제안
    'GENERAL_QA_ABOUT_CODE',        -- (향후 확장) 코드에 대한 일반적인 질의응답
    'OTHER_LLM_TASK'                -- 기타 LLM 작업 단계
);
COMMENT ON TYPE llm_call_stage_enum IS 'LLM 호출이 사용된 주요 단계를 나타내는 ENUM 타입입니다.';

CREATE TYPE llm_input_context_type_enum AS ENUM (
    -- 코드 자체 및 분석 결과
    'SNAPSHOT_FILE_INSTANCE_FULL_CODE', -- 특정 파일의 전체 코드 (snapshot_file_instances 참조)
    'SNAPSHOT_CODE_ELEMENT_INSTANCE_SNIPPET', -- 특정 코드 요소의 스니펫 (snapshot_code_element_instances 참조)
    'GENERATED_TECHNICAL_DESCRIPTION',  -- 1차 LLM 생성 기술 설명서 (generated_technical_descriptions 참조)
    'FILE_DIFF_FRAGMENT_TEXT',          -- Diff 조각 텍스트 (file_diff_fragments 참조)
    'FILE_ANALYSIS_METRIC_VALUE',       -- 파일 분석 메트릭 값 (file_analysis_metrics 참조)
    'CODE_ELEMENT_RELATION_INFO',       -- 코드 요소 간 관계 정보 (code_element_relations 참조)
    'EMBEDDING_SIMILARITY_SCORE',       -- 코드 요소 임베딩 기반 유사도 점수 (code_element_embeddings 또는 scoping_results 참조)

    -- 리포지토리 및 시스템 레벨 정보
    'REPOSITORY_METADATA',              -- 리포지토리 기본 정보 (repositories 참조)
    'PROJECT_README_SUMMARY',           -- 프로젝트 README 파일 요약본
    'DIRECTORY_STRUCTURE_OVERVIEW',     -- 디렉토리 구조 정보 (directory_structures 참조)
    'SCOPING_STRATEGY_APPLIED',         -- 적용된 스코핑 전략/규칙 요약
    'USER_DEFINED_COMMIT_RULE_TEXT',    -- 사용자 정의 커밋 규칙 텍스트
    'COMMIT_MESSAGE_TEMPLATE_TEXT',     -- 적용된 커밋 메시지 템플릿 텍스트

    -- 사용자 입력 및 지시사항
    'USER_DIRECT_INSTRUCTION',          -- 사용자가 직접 입력한 지시사항 또는 추가 컨텍스트
    'USER_FEEDBACK_ON_PREVIOUS_OUTPUT', -- 이전 LLM 출력에 대한 사용자 피드백

    -- 시스템 내부 정보
    'SYSTEM_LEVEL_PROMPT_CONFIGURATION',-- 시스템 레벨의 공통 프롬프트 또는 가이드라인
    'CURRENT_DATE_TIME_INFO',           -- 현재 날짜 및 시간 정보 (필요시)
    'TARGET_COMMIT_BRANCH_NAME',        -- 커밋 대상 브랜치 이름

    'OTHER_CONTEXT_ELEMENT'             -- 기타 분류되지 않은 컨텍스트 요소
);
COMMENT ON TYPE llm_input_context_type_enum IS 'LLM 호출 시 입력으로 사용된 컨텍스트 요소의 타입을 나타내는 ENUM 타입입니다.';


-- =====================================================================================
-- (선택적) 공통 복합 타입 (COMPOSITE TYPES)
-- =====================================================================================
-- 예시: 코드 내 위치 정보를 나타내는 복합 타입
-- CREATE TYPE code_location_type AS (
--     start_line INT,
--     end_line INT,
--     start_column INT,
--     end_column INT
-- );
-- COMMENT ON TYPE code_location_type IS '소스 코드 내의 특정 위치(시작/종료 라인 및 컬럼)를 나타내는 복합 타입입니다.';

-- 예시: 점수와 설명을 함께 가지는 복합 타입
-- CREATE TYPE scored_description_type AS (
--     score NUMERIC,
--     description TEXT
-- );
-- COMMENT ON TYPE scored_description_type IS '점수와 관련 설명을 함께 저장하는 복합 타입입니다.';

SELECT 'ENUM and custom types for 04_repo_module created successfully.' AS status;