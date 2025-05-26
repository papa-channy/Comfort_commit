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
    'LANGUAGE_uuidENTIFIED',          -- 식별된 프로그래밍 언어 (예: 'Python', 'JavaScript')

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
    'POTENTIAL_REFACTORING_CANDuuidATE_SCORE', -- 리팩토링 후보로서의 잠재력 점수

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

-- `01_code_element_uuidentities.sql` 및 `02_snapshot_code_element_instances.sql` 에서 사용
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
    'SCOPING_INITIAL_CANDuuidATES',   -- 초기 스코핑 후보군 생성 중
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

-- =====================================================================================
-- 파일: 01_repo.sql
-- 모듈: 04_repo_module / 01_repositories (저장소 기본 정보)
-- 설명: 사용자가 Comfort Commit 서비스에 등록하는 소스 코드 저장소의 마스터 정보 및
--       서비스 운영에 필요한 주요 Git 메타데이터를 관리합니다.
-- 대상 DB: PostgreSQL Primary RDB (저장소 메타데이터)
-- 파티셔닝: 없음
-- MVP 중점사항: 핵심 식별 정보, Git 명령어 기반 주요 메타데이터(URL, 크기, 파일 수 등),
--             소유자, VCS 플랫폼, 가시성, 표준 created_at/updated_at.
-- 스케일업 고려사항: RLS 적용, 저장소별 상세 설정(JSONB), 메타데이터 주기적 업데이트 로직 및 last_analyzed_at 컬럼 추가.
-- =====================================================================================

-- ENUM 타입 정의 (필요시 04_repo_module/00_repo_enums_and_types.sql 파일로 통합 예정)
CREATE TYPE repo_vcs_platform_enum AS ENUM ('github', 'gitlab', 'bitbucket', 'other');
COMMENT ON TYPE repo_vcs_platform_enum IS '저장소가 호스팅되는 Version Control System 플랫폼 유형입니다.';

CREATE TYPE repo_visibility_enum AS ENUM ('public', 'private', 'internal');
COMMENT ON TYPE repo_visibility_enum IS '저장소의 공개 범위입니다.';

-- 테이블명: repo_main
CREATE TABLE repo_main (
    repo_id id PRIMARY KEY DEFAULT gen_random_id(),    -- 저장소의 고유 식별자 (PK)
    owner_id id NOT NULL REFERENCES user_info(id) ON DELETE RESTRICT, -- 이 저장소를 서비스에 등록한 소유 사용자
    
    name TEXT NOT NULL,                                      -- 저장소 이름 (VCS 플랫폼 기준)
    vcs_platform repo_vcs_platform_enum NOT NULL,            -- 저장소가 호스팅되는 VCS 플랫폼
    remote_url TEXT UNIQUE,                                  -- 'origin' 원격 저장소 URL (git config --get remote.origin.url 결과). 고유해야 함. [cite: 1, 9]
    visibility repo_visibility_enum DEFAULT 'private',      -- 저장소의 공개 범위 (VCS 플랫폼 기준)
    
    default_branch_name TEXT DEFAULT 'main',                 -- 저장소의 기본 브랜치명
    repository_created_at_on_platform TIMESTAMP,             -- VCS 플랫폼에서 저장소가 실제로 생성된 시각
    description_text TEXT,                                   -- 저장소 설명
    primary_language_detected TEXT,                          -- 주 사용 언어 (자동 감지 결과)
    
    -- Git 명령어 기반 분석 정보 (Comfort Commit 내부 분류 및 스코핑 전략에 활용)
    total_file_count INT,                                    -- 저장소 내 추적되는 총 파일 개수 (git ls-files | wc -l 또는 git ls-tree 결과 기반) [cite: 1, 18, 39]
    analyzable_file_count INT,                               -- 분석 대상 파일 개수 (예: 특정 확장자, .gitignore 제외)
    repository_size_kb BIGINT,                               -- 저장소의 디스크 사용량 (KB) (git count-objects -vH 결과 기반) [cite: 1, 20]
    last_analyzed_git_info_at TIMESTAMP,                     -- 위 Git 기반 분석 정보들이 마지막으로 업데이트된 시각

    archived_status BOOLEAN DEFAULT FALSE,                   -- VCS 플랫폼에서 아카이브된 상태인지 여부
    service_registration_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, -- Comfort Commit 서비스에 이 저장소가 등록된 시각
    
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, -- 이 레코드가 Comfort Commit DB에 생성된 시각
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP  -- 이 레코드의 메타데이터가 마지막으로 수정된 시각 (트리거로 자동 관리)

    CONSTRAINT uq_repo_main_owner_platform_name UNIQUE (owner_id, vcs_platform, name) -- 한 사용자가 동일 플랫폼에 동일 이름의 저장소를 중복 등록 방지
);

COMMENT ON TABLE repo_main IS 'Comfort Commit 서비스에 등록된 외부 소스 코드 저장소의 기본 마스터 정보 및 주요 Git 메타데이터를 저장합니다.';
COMMENT ON COLUMN repo_main.repo_id IS '저장소의 서비스 내 고유 식별 id입니다.';
COMMENT ON COLUMN repo_main.owner_id IS '이 저장소를 Comfort Commit 서비스에 등록하고 기본 소유권을 가지는 사용자의 id (user_info.id 참조)입니다.';
COMMENT ON COLUMN repo_main.name IS 'VCS 플랫폼에서의 저장소 이름입니다.';
COMMENT ON COLUMN repo_main.vcs_platform IS '저장소가 호스팅되는 Version Control System 플랫폼의 유형입니다.';
COMMENT ON COLUMN repo_main.remote_url IS '저장소의 원격 URL (예: git clone 주소) 입니다. 일반적으로 origin을 기준으로 합니다. [cite: 1, 9]';
COMMENT ON COLUMN repo_main.total_file_count IS 'Git이 추적하는 저장소 내 총 파일 수입니다. 레포 크기 분류에 사용될 수 있습니다. [cite: 1, 18, 39]';
COMMENT ON COLUMN repo_main.analyzable_file_count IS 'Comfort Commit 분석 대상이 되는 유효 파일 수입니다 (예: 데이터 파일, 바이너리 제외).';
COMMENT ON COLUMN repo_main.repository_size_kb IS '저장소가 디스크에서 차지하는 대략적인 크기(KB)입니다. 레포 크기 분류에 사용될 수 있습니다. [cite: 1, 20]';
COMMENT ON COLUMN repo_main.last_analyzed_git_info_at IS 'total_file_count, repository_size_kb 등의 Git 기반 분석 정보가 마지막으로 갱신된 시각입니다.';
COMMENT ON COLUMN repo_main.updated_at IS '이 저장소 메타데이터 레코드가 마지막으로 수정된 시각입니다.';

-- 인덱스
CREATE INDEX uuidx_repo_main_owner_id ON repo_main(owner_id);
CREATE INDEX uuidx_repo_main_vcs_platform ON repo_main(vcs_platform);
-- remote_url은 UNIQUE 제약조건에 의해 자동으로 인덱싱됩니다.

-- updated_at 컬럼 자동 갱신 트리거
CREATE TRIGGER trg_set_updated_at_repo_main
BEFORE UPDATE ON repo_main
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =====================================================================================
-- 파일: 02_repo_connections.sql
-- 모듈: 04_repo_module / 01_repositories (저장소 기본 정보)
-- 설명: Comfort Commit 서비스와 등록된 저장소 간의 연동 상태, 서비스별 설정,
--       및 마지막 연결/작업 환경 정보를 관리합니다.
-- 대상 DB: PostgreSQL Primary RDB (저장소 연동 상태 및 설정 데이터)
-- 파티셔닝: 없음
-- MVP 중점사항: 저장소별 연결 상태, 마지막 성공/시도 시각, 에러 상세, Webhook uuid,
--             토큰 참조 uuid, 서비스 설정 JSONB, 표준 created_at/updated_at.
-- 스케일업 고려사항: RLS 적용, 연결 히스토리 로그 분리, 설정 JSONB 필드 세분화,
--                  주기적인 연결 상태 자동 점검 및 알림.
-- =====================================================================================

-- ENUM 타입 정의 (필요시 04_repo_module/00_repo_enums_and_types.sql 파일로 통합 예정)
CREATE TYPE repo_connection_status_enum AS ENUM ('pending_verification', 'connected', 'disconnected_by_user', 'error_authentication', 'error_permissions', 'error_not_found', 'syncing', 'temporarily_unavailable');
COMMENT ON TYPE repo_connection_status_enum IS '저장소와 Comfort Commit 서비스 간의 연동 상태입니다.';

CREATE TYPE repo_connection_method_enum AS ENUM ('oauth_app', 'personal_access_token', 'ssh_key_reference', 'github_codespaces', 'other');
COMMENT ON TYPE repo_connection_method_enum IS '저장소에 접근하기 위해 우선적으로 사용되는 연결 방식입니다.';

-- 테이블명: repo_connections
CREATE TABLE repo_connections (
    repo_id id PRIMARY KEY REFERENCES repo_main(repo_id) ON DELETE CASCADE, -- repo_main 테이블의 저장소 id (PK, FK)
    
    connection_status repo_connection_status_enum DEFAULT 'pending_verification', -- 현재 연결 상태
    last_successful_connection_at TIMESTAMP,      -- 마지막으로 성공적인 연결(예: API 호출, Webhook 수신)이 있었던 시각
    last_connection_attempt_at TIMESTAMP,         -- 마지막 연결 시도 시각 (성공/실패 무관)
    connection_error_details TEXT,                -- 연결 실패 시 상세 오류 메시지 또는 코드
    
    webhook_uuid_on_platform TEXT,                  -- VCS 플랫폼에 등록된 Webhook의 uuid (Webhook을 사용하는 경우)
    access_token_ref_uuid TEXT,                     -- 이 저장소 접근에 사용되는 Access Token의 외부 저장소 참조 uuid 또는 Comfort Commit 내부 토큰 관리 시스템의 식별자. 실제 토큰 값은 저장하지 않음.
    preferred_connection_method repo_connection_method_enum, -- 사용자가 선호하거나 시스템이 주로 사용하는 연결 방식
    last_accessed_from_os TEXT,                   -- 마지막으로 이 저장소 관련 작업을 수행한 사용자 환경의 OS 정보 (선택적)

    comfort_commit_config_json JSONB DEFAULT '{}'::JSONB, -- 해당 저장소에 대한 Comfort Commit 서비스의 특화 설정 
                                                          -- 예: {"auto_analysis_enabled": true, "default_llm_model_for_repo": "gpt-4o", "commit_style_template_uuid": "id", "analysis_branch_filter": ["main", "develop"]}
    
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, -- 이 연결 설정 레코드가 생성된 시각
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP  -- 이 연결 설정 레코드가 마지막으로 수정된 시각 (트리거로 자동 관리)
);

COMMENT ON TABLE repo_connections IS 'Comfort Commit 서비스와 등록된 저장소 간의 연동 상태, 서비스별 설정, 마지막 연결 정보 등을 관리합니다.';
COMMENT ON COLUMN repo_connections.repo_id IS 'repo_main 테이블의 저장소 id를 참조하며, 이 테이블의 기본 키입니다.';
COMMENT ON COLUMN repo_connections.connection_status IS '현재 저장소와의 연동 상태를 나타냅니다 (예: connected, error_authentication).';
COMMENT ON COLUMN repo_connections.last_successful_connection_at IS '서비스가 저장소와 마지막으로 성공적인 상호작용(API 호출, Webhook 이벤트 수신 등)을 한 시각입니다.';
COMMENT ON COLUMN repo_connections.webhook_uuid_on_platform IS 'VCS 플랫폼(GitHub, GitLab 등)에 등록된 Webhook의 고유 uuid입니다. Webhook 기반 이벤트 수신 시 사용됩니다.';
COMMENT ON COLUMN repo_connections.access_token_ref_uuid IS '저장소 접근에 필요한 인증 토큰의 외부 보안 저장소 참조 uuid 또는 내부 토큰 관리 시스템의 식별자입니다. 실제 토큰은 여기에 저장되지 않습니다.';
COMMENT ON COLUMN repo_connections.preferred_connection_method IS '이 저장소에 접근하거나 사용자가 주로 사용하는 연결 방식입니다 (예: OAuth 앱, PAT).';
COMMENT ON COLUMN repo_connections.last_accessed_from_os IS '사용자가 마지막으로 이 저장소 관련 작업을 수행했을 때의 클라이언트 OS 정보입니다 (예: Windows, macOS, Linux).';
COMMENT ON COLUMN repo_connections.comfort_commit_config_json IS '이 특정 저장소에만 적용되는 Comfort Commit 서비스의 설정값을 JSONB 형태로 저장합니다 (예: 자동 분석 활성화 여부, 기본 LLM 모델 등).';
COMMENT ON COLUMN repo_connections.updated_at IS '이 연결 설정 정보가 마지막으로 수정된 시각입니다.';

-- 인덱스
CREATE INDEX uuidx_repo_connections_status ON repo_connections(connection_status); -- 특정 연결 상태의 저장소 조회
CREATE INDEX uuidx_repo_connections_access_token_ref ON repo_connections(access_token_ref_uuid) WHERE access_token_ref_uuid IS NOT NULL;
CREATE INDEX uuidx_repo_connections_webhook_uuid ON repo_connections(webhook_uuid_on_platform) WHERE webhook_uuid_on_platform IS NOT NULL;

-- updated_at 컬럼 자동 갱신 트리거
-- (set_updated_at() 함수는 '00_common_functions_and_types.sql' 파일에 정의될 예정)
CREATE TRIGGER trg_set_updated_at_repo_connections
BEFORE UPDATE ON repo_connections
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =====================================================================================
-- 파일: 03_repo_access_permissions.sql
-- 모듈: 04_repo_module / 01_repositories (저장소 기본 정보)
-- 설명: Comfort Commit 서비스 내에서 사용자별로 특정 저장소에 대한 접근 권한을 관리합니다.
--       이는 VCS 플랫폼 자체의 접근 권한과 별개로, 서비스 기능 사용 권한을 제어할 수 있습니다.
-- 대상 DB: PostgreSQL Primary RDB (접근 제어 데이터)
-- 파티셔닝: 없음
-- MVP 중점사항: 저장소-사용자-접근레벨 매핑, 권한 부여 주체, 유효 기간, 필수 인덱스, 표준 created_at/updated_at.
-- 스케일업 고려사항: RLS 적용, 권한 상속 규칙 (팀/조직 연동 시), 권한 변경 이력 로그 분리.
-- =====================================================================================

-- ENUM 타입 정의 (필요시 04_repo_module/00_repo_enums_and_types.sql 파일로 통합 예정)
CREATE TYPE repo_access_level_enum AS ENUM ('owner', 'admin', 'maintainer', 'developer', 'viewer', 'guest', 'no_access');
COMMENT ON TYPE repo_access_level_enum IS 'Comfort Commit 서비스 내에서 사용자의 특정 저장소에 대한 접근 수준을 정의합니다.';

-- 테이블명: repo_access_permissions
CREATE TABLE repo_access_permissions (
    permission_uuid id PRIMARY KEY DEFAULT gen_random_id(), -- 권한 레코드의 고유 식별자 (PK)
    repo_id id NOT NULL REFERENCES repo_main(repo_id) ON DELETE CASCADE, -- 권한 대상 저장소 (FK)
    user_id id NOT NULL REFERENCES user_info(id) ON DELETE CASCADE, -- 권한을 부여받는 사용자 (FK)
    
    access_level repo_access_level_enum NOT NULL,          -- 이 사용자에게 부여된 접근 수준
    
    granted_by_user_id id REFERENCES user_info(id) ON DELETE SET NULL, -- 이 권한을 부여한 사용자 (시스템 또는 저장소 소유자/관리자)
    permission_start_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, -- 권한 효력 시작일
    permission_end_date TIMESTAMP,                          -- 권한 효력 만료일 (NULL이면 영구)
    
    notes TEXT,                                             -- 권한 설정 관련 관리자 메모
    
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, -- 이 권한 레코드가 생성된 시각
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP  -- 이 권한 레코드가 마지막으로 수정된 시각 (트리거로 자동 관리)

    CONSTRAINT uq_repo_user_permission UNIQUE (repo_id, user_id) -- 한 사용자는 한 저장소에 대해 하나의 접근 권한만 가짐 (중복 방지)
);

COMMENT ON TABLE repo_access_permissions IS 'Comfort Commit 서비스 내에서 특정 저장소에 대한 사용자별 접근 권한을 정의하고 관리합니다.';
COMMENT ON COLUMN repo_access_permissions.permission_uuid IS '각 권한 설정 레코드의 고유 식별 id입니다.';
COMMENT ON COLUMN repo_access_permissions.repo_id IS '권한이 적용되는 대상 저장소의 id (repo_main.repo_id 참조)입니다.';
COMMENT ON COLUMN repo_access_permissions.user_id IS '접근 권한을 부여받는 사용자의 id (user_info.id 참조)입니다.';
COMMENT ON COLUMN repo_access_permissions.access_level IS '부여된 접근 권한의 수준입니다 (예: owner, admin, viewer).';
COMMENT ON COLUMN repo_access_permissions.granted_by_user_id IS '이 접근 권한을 부여한 관리자 또는 시스템 주체의 사용자 id입니다.';
COMMENT ON COLUMN repo_access_permissions.permission_start_date IS '이 접근 권한이 효력을 발휘하기 시작하는 시각입니다.';
COMMENT ON COLUMN repo_access_permissions.permission_end_date IS '이 접근 권한의 효력이 만료되는 시각입니다. NULL인 경우 영구적인 권한을 의미합니다.';
COMMENT ON COLUMN repo_access_permissions.notes IS '이 권한 설정에 대한 추가적인 설명이나 관리자 메모입니다.';
COMMENT ON COLUMN repo_access_permissions.updated_at IS '이 권한 정보가 마지막으로 수정된 시각입니다.';
COMMENT ON CONSTRAINT uq_repo_user_permission ON repo_access_permissions IS '한 명의 사용자는 특정 저장소에 대해 하나의 접근 권한 레벨만 가질 수 있도록 보장합니다.';

-- 인덱스
CREATE INDEX uuidx_repo_access_permissions_user_id ON repo_access_permissions(user_id); -- 특정 사용자가 접근 가능한 저장소 목록 조회 시 사용 (원본 컬럼명 변경 없음)
CREATE INDEX uuidx_repo_access_permissions_repo_id ON repo_access_permissions(repo_id); -- 특정 저장소에 접근 권한이 있는 사용자 목록 조회 시 사용 (원본 컬럼명 변경 없음)
CREATE INDEX uuidx_repo_access_permissions_repo_user_level ON repo_access_permissions(repo_id, user_id, access_level); -- 특정 저장소, 사용자의 특정 권한 확인

-- updated_at 컬럼 자동 갱신 트리거
-- (set_updated_at() 함수는 '00_common_functions_and_types.sql' 파일에 정의될 예정)
CREATE TRIGGER trg_set_updated_at_repo_access_permissions
BEFORE UPDATE ON repo_access_permissions
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =====================================================================================
-- 파일: 01_code_snapshots.sql
-- 모듈: 04_repo_module / 02_code_snapshots (코드 스냅샷 관리)
-- 설명: 특정 Git 커밋 해시를 기준으로 저장소의 특정 시점 상태(스냅샷)에 대한 메타데이터를 관리합니다.
--       이 스냅샷은 Comfort Commit의 모든 코드 분석 및 커밋 생성 작업의 기준이 됩니다.
-- 대상 DB: PostgreSQL Primary RDB (코드 분석 기준 데이터)
-- 파티셔닝: 고려 가능 (repo_id, committed_at_on_platform 기준으로, 데이터가 매우 많아질 경우 - 스케일업 시)
-- MVP 중점사항: 스냅샷 식별 정보(커밋 해시), 부모 커밋, 커미터 정보, 분석 트리거 및 상태, 필수 인덱스.
-- 스케일업 고려사항: RLS 적용, 파티셔닝, 분석 결과 요약 정보 추가, 스냅샷 간의 비교 기능 지원.
-- =====================================================================================

-- ENUM 타입 정의 (필요시 04_repo_module/00_repo_enums_and_types.sql 파일로 통합 예정)
CREATE TYPE snapshot_analysis_status_enum AS ENUM ('pending', 'queued', 'processing', 'completed', 'partial_success', 'failed', 'cancelled_by_user', 'error_internal');
COMMENT ON TYPE snapshot_analysis_status_enum IS '코드 스냅샷에 대한 Comfort Commit 내부 분석 작업의 진행 상태입니다.';

CREATE TYPE snapshot_trigger_event_enum AS ENUM ('webhook_push', 'manual_sync_repo', 'scheduled_repo_scan', 'initial_repo_registration', 'commit_generation_request_target');
COMMENT ON TYPE snapshot_trigger_event_enum IS '이 코드 스냅샷 분석을 트리거한 이벤트의 유형입니다.';

-- 테이블명: code_snapshots
CREATE TABLE code_snapshots (
    snapshot_id id PRIMARY KEY DEFAULT gen_random_id(),    -- 코드 스냅샷의 고유 식별자 (PK)
    repo_id id NOT NULL REFERENCES repo_main(repo_id) ON DELETE CASCADE, -- 이 스냅샷이 속한 저장소 (FK)
    
    git_commit_hash TEXT NOT NULL,                               -- 해당 스냅샷의 기준이 되는 Git 커밋 해시 (SHA-1 또는 SHA-256)
    parent_commit_hashes TEXT[],                                 -- 이 커밋의 부모 커밋 해시 목록 (Merge commit의 경우 여러 개일 수 있음)
    commit_message_original TEXT,                                -- 원본 Git 커밋 메시지
    committer_name TEXT,                                         -- 원본 커밋의 커미터 이름
    committer_email TEXT,                                        -- 원본 커밋의 커미터 이메일
    committed_at_on_platform TIMESTAMP,                          -- Git 플랫폼(예: GitHub)에서의 실제 커밋 시각
    
    analysis_trigger_event snapshot_trigger_event_enum,         -- 이 스냅샷에 대한 분석을 시작하게 된 이벤트 유형
    analysis_start_time TIMESTAMP,                               -- Comfort Commit 내부 분석 시작 시각
    analysis_end_time TIMESTAMP,                                 -- Comfort Commit 내부 분석 완료 시각
    analysis_status snapshot_analysis_status_enum DEFAULT 'pending', -- Comfort Commit 내부 분석 상태
    analysis_error_details TEXT,                                 -- 분석 실패 시 상세 오류 메시지
    
    snapshot_created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, -- 이 스냅샷 레코드가 Comfort Commit DB에 생성된 시각
    -- updated_at은 분석 상태 변경 등에 따라 필요할 수 있으나, 스냅샷 자체의 메타데이터는 불변으로 간주하여 MVP에서는 제외.
    -- 필요시 추가하고 트리거 설정 가능.

    CONSTRAINT uq_code_snapshots_repo_commit_hash UNIQUE (repo_id, git_commit_hash) -- 한 저장소 내에서 특정 커밋 해시에 대한 스냅샷은 유일해야 함
);

COMMENT ON TABLE code_snapshots IS '특정 Git 커밋을 기준으로 생성된 저장소의 코드 스냅샷 메타데이터를 저장합니다. 모든 분석과 커밋 생성은 이 스냅샷을 기준으로 이루어집니다.';
COMMENT ON COLUMN code_snapshots.snapshot_id IS '코드 스냅샷 레코드의 고유 식별 id입니다.';
COMMENT ON COLUMN code_snapshots.repo_id IS '이 코드 스냅샷이 속한 저장소의 id (repo_main.repo_id 참조)입니다.';
COMMENT ON COLUMN code_snapshots.git_commit_hash IS '이 스냅샷의 기준이 되는 Git 커밋의 전체 해시값입니다.';
COMMENT ON COLUMN code_snapshots.parent_commit_hashes IS '이 스냅샷의 기준 커밋의 부모 커밋 해시 목록입니다. Merge commit인 경우 두 개 이상의 부모를 가질 수 있습니다.';
COMMENT ON COLUMN code_snapshots.commit_message_original IS 'VCS 플랫폼에 기록된 원본 커밋 메시지입니다.';
COMMENT ON COLUMN code_snapshots.committer_name IS 'VCS 플랫폼에 기록된 원본 커밋의 커미터 이름입니다.';
COMMENT ON COLUMN code_snapshots.committer_email IS 'VCS 플랫폼에 기록된 원본 커밋의 커미터 이메일입니다.';
COMMENT ON COLUMN code_snapshots.committed_at_on_platform IS 'VCS 플랫폼(GitHub, GitLab 등)에 해당 커밋이 기록된 실제 시각입니다.';
COMMENT ON COLUMN code_snapshots.analysis_trigger_event IS 'Comfort Commit 시스템이 이 스냅샷에 대한 분석을 시작하게 된 계기입니다 (예: Webhook push, 수동 동기화).';
COMMENT ON COLUMN code_snapshots.analysis_status IS 'Comfort Commit 시스템의 내부 코드 분석 작업 진행 상태입니다.';
COMMENT ON COLUMN code_snapshots.snapshot_created_at IS '이 스냅샷 정보 레코드가 Comfort Commit 데이터베이스에 처음 생성된 시각입니다.';
COMMENT ON CONSTRAINT uq_code_snapshots_repo_commit_hash ON code_snapshots IS '동일한 저장소 내에서 동일한 Git 커밋 해시를 가진 스냅샷은 중복으로 생성될 수 없습니다.';

-- 인덱스
CREATE INDEX uuidx_code_snapshots_repo_commit_hash ON code_snapshots(repo_id, git_commit_hash); -- 특정 저장소의 특정 커밋 스냅샷 조회 (UNIQUE 제약으로 커버되지만 명시적 생성도 가능)
CREATE INDEX uuidx_code_snapshots_repo_status_created_at ON code_snapshots(repo_id, analysis_status, snapshot_created_at DESC); -- 특정 저장소의 분석 상태별 최근 스냅샷 조회
CREATE INDEX uuidx_code_snapshots_committed_at_on_platform ON code_snapshots(committed_at_on_platform DESC); -- 커밋 시간 기준 정렬/조회
CREATE INDEX uuidx_code_snapshots_analysis_trigger_event ON code_snapshots(analysis_trigger_event);

-- =====================================================================================
-- 파일: 02_directory_structures.sql
-- 모듈: 04_repo_module / 02_code_snapshots (코드 스냅샷 관리)
-- 설명: 특정 코드 스냅샷 시점에서의 저장소 디렉토리 구조를 계층적으로 저장합니다.
--       각 레코드는 하나의 디렉토리를 나타냅니다.
-- 대상 DB: PostgreSQL Primary RDB (코드 구조 메타데이터)
-- 파티셔닝: 고려 가능 (snapshot_id 기준으로, 매우 큰 저장소의 많은 스냅샷 관리 시 - 스케일업 시)
-- MVP 중점사항: 스냅샷별 디렉토리 경로, 부모-자식 관계, 중첩 레벨, 필수 인덱스.
-- 스케일업 고려사항: RLS 적용, 파티셔닝, 디렉토리별 통계(파일 수, 하위 디렉토리 수) 요약 정보 추가, tree_structure_json 최적화.
-- =====================================================================================

-- 테이블명: directory_structures
CREATE TABLE directory_structures (
    directory_uuid id PRIMARY KEY DEFAULT gen_random_id(), -- 디렉토리 레코드의 고유 식별자 (PK)
    snapshot_id id NOT NULL REFERENCES code_snapshots(snapshot_id) ON DELETE CASCADE, -- 이 디렉토리 구조가 속한 코드 스냅샷 (FK)
    
    parent_directory_uuid id REFERENCES directory_structures(directory_uuid) ON DELETE CASCADE, -- 부모 디렉토리의 uuid (최상위 디렉토리의 경우 NULL)
                                                                                             -- 자식 디렉토리는 부모가 삭제되면 함께 삭제 (계층 구조 유지)
    directory_path_text TEXT NOT NULL,                         -- 저장소 루트로부터의 전체 디렉토리 경로 (예: "src/main/java/com/example")
    directory_name TEXT NOT NULL,                              -- 해당 디렉토리의 이름 (예: "example")
    nesting_level INT NOT NULL CHECK (nesting_level >= 0),     -- 루트 디렉토리로부터의 중첩 깊이 (루트는 0)
    
    -- 스케일업 시 고려: 디렉토리 내 파일 수, 하위 디렉토리 수, 총 크기 등 요약 정보
    -- file_count_in_dir INT,
    -- subdirectory_count_in_dir INT,

    tree_structure_json JSONB,                                 -- 이 디렉토리 하위의 파일 및 서브디렉토리 목록을 간략하게 표현한 JSON (선택적, UI 표시 최적화용 또는 빠른 탐색용).
                                                               -- 예: {"files": ["file1.py", "file2.js"], "dirs": ["subdir1", "subdir2"]}
    
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,   -- 이 디렉토리 레코드가 DB에 생성된 시각
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP    -- 이 디렉토리 레코드 정보가 마지막으로 수정된 시각 (트리거로 자동 관리)

    CONSTRAINT uq_directory_structures_snapshot_dir_path UNIQUE (snapshot_id, directory_path_text) -- 동일 스냅샷 내에 중복된 전체 디렉토리 경로 방지
);

COMMENT ON TABLE directory_structures IS '특정 코드 스냅샷의 디렉토리 계층 구조를 나타냅니다. 각 레코드는 하나의 디렉토리를 의미합니다.';
COMMENT ON COLUMN directory_structures.directory_uuid IS '각 디렉토리 항목의 고유 식별 id입니다.';
COMMENT ON COLUMN directory_structures.snapshot_id IS '이 디렉토리 구조가 포함된 code_snapshots 테이블의 스냅샷 id입니다.';
COMMENT ON COLUMN directory_structures.parent_directory_uuid IS '이 디렉토리의 바로 상위 부모 디렉토리의 uuid (directory_structures.directory_uuid 참조)입니다. 루트 디렉토리의 경우 NULL 값을 가집니다.';
COMMENT ON COLUMN directory_structures.directory_path_text IS '저장소의 루트 디렉토리로부터 해당 디렉토리까지의 전체 경로 문자열입니다 (예: "src/main/java").';
COMMENT ON COLUMN directory_structures.directory_name IS '해당 디렉토리의 이름입니다 (예: "java").';
COMMENT ON COLUMN directory_structures.nesting_level IS '루트 디렉토리(0)로부터 해당 디렉토리까지의 중첩 단계(깊이)입니다.';
COMMENT ON COLUMN directory_structures.tree_structure_json IS '선택적으로, 해당 디렉토리 바로 하위의 파일 및 서브디렉토리 목록을 JSON 형태로 저장하여 UI 등에서 빠르게 트리를 구성하는 데 사용될 수 있습니다.';
COMMENT ON COLUMN directory_structures.updated_at IS '이 디렉토리 구조 정보가 마지막으로 수정된 시각입니다.';
COMMENT ON CONSTRAINT uq_directory_structures_snapshot_dir_path ON directory_structures IS '하나의 코드 스냅샷 내에서는 동일한 전체 디렉토리 경로가 중복으로 존재할 수 없습니다.';

-- 인덱스
CREATE INDEX uuidx_directory_structures_snapshot_parent ON directory_structures(snapshot_id, parent_directory_uuid); -- 특정 스냅샷의 특정 부모 디렉토리 하위 항목 조회
CREATE INDEX uuidx_directory_structures_snapshot_path ON directory_structures(snapshot_id, directory_path_text); -- 스냅샷 내 경로 검색 (UNIQUE 제약으로 커버되지만 명시적 생성도 가능)
-- 원본의 GIN 인덱스는 전체 텍스트 검색용이지만, 여기서는 정확한 경로 매칭이 더 중요할 수 있음. 필요시 to_tsvector 사용한 GIN 인덱스 유지 가능.
-- CREATE INDEX uuidx_ds_path_text_gin ON directory_structures USING GIN (to_tsvector('simple', directory_path_text)); -- 원본 유지 시
CREATE INDEX uuidx_directory_structures_path_prefix ON directory_structures(directory_path_text text_pattern_ops); -- 경로 prefix 검색 최적화 (예: 'src/main/%' 검색)

-- updated_at 컬럼 자동 갱신 트리거
-- (set_updated_at() 함수는 '00_common_functions_and_types.sql' 파일에 정의될 예정)
CREATE TRIGGER trg_set_updated_at_directory_structures
BEFORE UPDATE ON directory_structures
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =====================================================================================
-- 파일: 03_file_diff_fragments.sql
-- 모듈: 04_repo_module / 02_code_snapshots (스냅샷 시점 구조 저장)
-- 설명: 특정 스냅샷에서 변경된 파일들의 Diff 정보를 저장합니다.
--       LLM 프롬프트 입력에 활용될 수 있도록 변경된 라인, 유형 등의 요약 정보를 포함하며,
--       필요에 따라 원본 Diff 데이터는 외부 저장소(예: S3)에 저장하고 참조 uuid를 가질 수 있습니다.
-- 대상 DB: PostgreSQL Primary RDB
-- 파티셔닝: 대량의 Diff 데이터 발생 시 고려 가능 (예: snapshot_uuid 또는 created_at 기준)
-- MVP 중점사항: 스냅샷 파일별 Diff 조각 정보, 변경 유형, 변경 라인, LLM 활용을 위한 핵심 정보.
-- 스케일업 고려사항: RLS, 파티셔닝, 외부 저장소 연동 강화, Hunk 단위 상세 분석, Diff 파싱 라이브러리와의 연동.
-- =====================================================================================

CREATE TABLE file_diff_fragments (
    diff_fragment_uuid id PRIMARY KEY DEFAULT gen_random_id(), -- Diff 조각 레코드의 고유 식별자

    snapshot_file_uuid id NOT NULL REFERENCES snapshot_file_instances(snapshot_file_uuid) ON DELETE CASCADE,
    -- 이 Diff 정보가 속한 스냅샷의 특정 파일 인스턴스 (snapshot_file_instances.snapshot_file_uuid 참조)
    -- ON DELETE CASCADE: 부모 스냅샷 파일 인스턴스가 삭제되면 해당 Diff 정보도 함께 삭제

    -- Diff 요약 정보 (LLM 프롬프트용)
    change_type diff_change_type_enum NOT NULL, -- 변경 유형 (예: 'ADDED', 'MODIFIED', 'DELETED', 'RENAMED', 'COPIED')
                                             -- (00_repo_enums_and_types.sql 에 정의될 ENUM)
    -- 변경된 라인 수 정보
    lines_added INT DEFAULT 0,
    lines_deleted INT DEFAULT 0,
    -- lines_modified INT, -- 일반적으로 added/deleted로 표현되므로 중복될 수 있으나, 필요시 추가

    -- 변경된 주요 코드 블록 또는 라인 범위 (간단한 요약 또는 시작/종료 라인)
    -- MVP에서는 단순 TEXT로 시작하거나, 더 구조화된 표현(예: JSONB)으로 확장 가능
    changed_lines_summary TEXT,
    -- 예: "L10-L15: 함수 시그니처 변경, L20-L25: 로직 추가" 또는
    -- JSONB: [{"start_line": 10, "end_line": 15, "description": "function signature change"}, ...]

    -- Hunk 단위 정보 (Git Diff의 Hunk 헤더 정보 등) - 스케일업 시 고려
    -- hunk_details JSONB,
    -- 예: [{"old_start_line": 5, "old_lines_count": 3, "new_start_line": 5, "new_lines_count": 7, "header_text": "@@ -5,3 +5,7 @@"}, ...]

    -- 원본 Diff 데이터 참조 (선택적)
    raw_diff_content TEXT, -- 짧은 Diff의 경우 직접 저장 가능 (PII 및 저장 공간 고려)
    external_diff_storage_url TEXT, -- 긴 Diff는 S3 등 외부 저장소에 저장 후 URL 또는 uuid 참조
    external_diff_checksum TEXT,    -- 외부 저장된 Diff의 무결성 검증용 체크섬 (예: SHA256)

    -- LLM 처리 관련 메타데이터 (선택적)
    is_llm_input_canduuidate BOOLEAN DEFAULT TRUE, -- 이 Diff 조각이 LLM 입력 후보로 사용될 수 있는지 여부
    llm_processing_notes TEXT,                 -- LLM 처리 시 참고할 만한 특이사항 (예: "매우 큰 변경", "주석만 변경됨")

    --  auditing
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE file_diff_fragments IS '특정 스냅샷에서 변경된 파일의 Diff 정보를 요약하거나 원본을 참조하여 저장합니다. LLM 프롬프트 생성에 활용됩니다.';
COMMENT ON COLUMN file_diff_fragments.snapshot_file_uuid IS 'Diff 정보가 속한 스냅샷 내 파일 인스턴스의 uuid (snapshot_file_instances.snapshot_file_uuid 참조)입니다.';
COMMENT ON COLUMN file_diff_fragments.change_type IS '파일의 변경 유형을 나타냅니다 (00_repo_enums_and_types.sql에 정의된 diff_change_type_enum 값).';
COMMENT ON COLUMN file_diff_fragments.lines_added IS '해당 Diff에서 추가된 라인 수입니다.';
COMMENT ON COLUMN file_diff_fragments.lines_deleted IS '해당 Diff에서 삭제된 라인 수입니다.';
COMMENT ON COLUMN file_diff_fragments.changed_lines_summary IS '변경된 주요 라인 범위나 코드 블록에 대한 텍스트 요약 또는 JSONB 형태의 구조화된 정보입니다.';
COMMENT ON COLUMN file_diff_fragments.raw_diff_content IS '짧은 원본 Diff 내용을 직접 저장하는 필드입니다. 민감 정보 및 저장 공간을 고려하여 사용합니다.';
COMMENT ON COLUMN file_diff_fragments.external_diff_storage_url IS '원본 Diff 데이터가 외부 저장소(예: S3)에 저장된 경우 해당 URL 또는 식별자입니다.';
COMMENT ON COLUMN file_diff_fragments.external_diff_checksum IS '외부 저장소에 저장된 Diff 데이터의 무결성 검증을 위한 체크섬 값입니다.';
COMMENT ON COLUMN file_diff_fragments.is_llm_input_canduuidate IS '이 Diff 조각이 LLM의 입력으로 사용될 후보인지 여부를 나타냅니다.';
COMMENT ON COLUMN file_diff_fragments.llm_processing_notes IS 'LLM이 이 Diff를 처리할 때 참고할 만한 추가적인 메모입니다.';


-- 인덱스
CREATE INDEX uuidx_file_diff_fragments_snapshot_file_uuid ON file_diff_fragments(snapshot_file_uuid);
CREATE INDEX uuidx_file_diff_fragments_change_type ON file_diff_fragments(change_type);
CREATE INDEX uuidx_file_diff_fragments_is_llm_canduuidate ON file_diff_fragments(is_llm_input_canduuidate) WHERE is_llm_input_canduuidate = TRUE;

-- updated_at 컬럼 자동 갱신 트리거 (00_common_functions_and_types.sql 에 set_updated_at 함수 정의 가정)
CREATE TRIGGER trg_set_updated_at_file_diff_fragments
BEFORE UPDATE ON file_diff_fragments
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- (00_repo_enums_and_types.sql 에 정의될 ENUM 예시)
-- CREATE TYPE diff_change_type_enum AS ENUM (
--     'ADDED',       -- 파일 추가
--     'MODIFIED',    -- 파일 내용 수정
--     'DELETED',     -- 파일 삭제
--     'RENAMED',     -- 파일 이름 변경 (내용 변경도 포함될 수 있음)
--     'COPIED',      -- 파일 복사
--     'TYPE_CHANGED' -- 파일 타입 변경 (예: 심볼릭 링크 -> 파일)
-- );

-- =====================================================================================
-- 파일: 01_file_uuidentities.sql
-- 모듈: 04_repo_module / 03_files (파일 정보 관리)
-- 설명: 저장소 내 각 파일의 고유한 식별 정보를 관리합니다. 파일의 경로 변경이나 삭제와 관계없이
--       파일 자체의 생명주기를 추적하기 위한 마스터 테이블입니다.
-- 대상 DB: PostgreSQL Primary RDB (파일 메타데이터)
-- 파티셔닝: 없음 (파일 경로 변경 추적이 복잡해질 수 있어, repo_id 기준으로 고려 가능 - 스케일업 시)
-- MVP 중점사항: 파일 고유 식별자, 최초 경로, 최초 식별 스냅샷, 필수 인덱스.
-- 스케일업 고려사항: RLS 적용, 파일 해시 기반 식별 (내용 동일 파일 추적), 파일 타입/용도 메타데이터 추가.
-- =====================================================================================

-- 테이블명: file_uuidentities
CREATE TABLE file_uuidentities (
    file_uuidentity_id id PRIMARY KEY DEFAULT gen_random_id(), -- 파일의 고유 식별자 (PK)
    repo_id id NOT NULL REFERENCES repo_main(repo_id) ON DELETE CASCADE, -- 이 파일 식별 정보가 속한 저장소 (FK)
    
    initial_file_path TEXT NOT NULL,                         -- 이 파일이 저장소 내에서 처음으로 식별되었을 때의 전체 경로
                                                             -- (예: "src/main/java/com/example/App.java")
    created_at_snapshot_id id NOT NULL REFERENCES code_snapshots(snapshot_id) ON DELETE RESTRICT, -- 이 파일이 처음 식별된 코드 스냅샷의 id (FK).
                                                                                                     -- 스냅샷 삭제 시 파일 식별자 자체는 유지될 수 있도록 RESTRICT.
                                                                                                     -- 만약 스냅샷 삭제 시 관련 파일 식별자도 의미가 없다면 CASCADE.
    -- 스케일업 시 고려:
    -- initial_content_hash TEXT,                           -- 처음 식별 시점의 파일 내용 해시 (선택적)
    -- initial_detected_language file_detected_language_enum, -- 처음 식별 시점의 감지된 언어 (snapshot_file_instances와 중복될 수 있으나, 최초 정보 기록용)

    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,   -- 이 파일 식별자 레코드가 DB에 생성된 시각
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP    -- 이 파일 식별자 레코드 정보가 마지막으로 수정된 시각 (트리거로 자동 관리)

    CONSTRAINT uq_file_uuidentities_repo_initial_path UNIQUE (repo_id, initial_file_path) -- 동일 저장소 내에서 동일한 초기 경로를 가진 파일 식별자는 중복될 수 없음
);

COMMENT ON TABLE file_uuidentities IS '저장소 내 각 파일의 고유한 식별 정보를 기록하여, 파일명/경로 변경에도 불구하고 파일의 생명주기를 추적할 수 있도록 합니다.';
COMMENT ON COLUMN file_uuidentities.file_uuidentity_id IS '각 파일 식별 정보 레코드의 고유 id입니다.';
COMMENT ON COLUMN file_uuidentities.repo_id IS '이 파일이 속한 저장소의 id (repo_main.repo_id 참조)입니다.';
COMMENT ON COLUMN file_uuidentities.initial_file_path IS '이 파일이 해당 저장소에서 처음으로 감지되었을 때의 전체 경로입니다.';
COMMENT ON COLUMN file_uuidentities.created_at_snapshot_id IS '이 파일이 처음으로 식별된 code_snapshots 테이블의 스냅샷 id입니다.';
COMMENT ON COLUMN file_uuidentities.created_at IS '이 파일 식별자 레코드가 데이터베이스에 처음 생성된 시각입니다.';
COMMENT ON COLUMN file_uuidentities.updated_at IS '이 파일 식별자 정보가 마지막으로 수정된 시각입니다 (예: 경로 정규화 규칙 변경 시).';
COMMENT ON CONSTRAINT uq_file_uuidentities_repo_initial_path ON file_uuidentities IS '하나의 저장소 내에서는 동일한 초기 파일 경로를 가진 파일 식별자가 중복으로 존재할 수 없습니다.';

-- 인덱스
CREATE INDEX uuidx_file_uuidentities_repo_path ON file_uuidentities(repo_id, initial_file_path); -- 특정 저장소의 특정 초기 경로 파일 식별자 조회 (UNIQUE 제약으로 커버되지만 명시적 생성도 가능)
CREATE INDEX uuidx_file_uuidentities_created_at_snapshot ON file_uuidentities(created_at_snapshot_id); -- 특정 스냅샷에서 처음 식별된 파일들 조회

-- updated_at 컬럼 자동 갱신 트리거
-- (set_updated_at() 함수는 '00_common_functions_and_types.sql' 파일에 정의될 예정)
CREATE TRIGGER trg_set_updated_at_file_uuidentities
BEFORE UPDATE ON file_uuidentities
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =====================================================================================
-- 파일: 03_file_analysis_metrics.sql
-- 모듈: 04_repo_module / 03_files (파일 정보 관리)
-- 설명: 특정 스냅샷의 파일 인스턴스에 대한 다양한 "파일 메타정보" 및 "작업 흐름도 관련 정보"를
--       저장합니다. 이 정보는 LLM 호출 시 파일의 특성 및 상태를 이해시키는 데 활용될 수 있습니다.
--       (예: 코드 라인 수, 주석 비율, 최근 수정 강도, 의존성 복잡도 등)
-- 대상 DB: PostgreSQL Primary RDB
-- 파티셔닝: 고려 가능 (snapshot_file_uuid 또는 analysis_timestamp 기준으로, 데이터가 매우 많아질 경우)
-- MVP 중점사항: 파일 인스턴스별 메타정보 기록, 메트릭 타입(ENUM), 값(숫자/텍스트/JSON), 분석 도구/로직명, 필수 인덱스.
-- 스케일업 고려사항: RLS, 파티셔닝, 표준화된 분석 결과 포맷 정의, 메트릭 변화 추이 분석 기능 지원.
-- =====================================================================================

CREATE TABLE file_analysis_metrics (
    metric_uuid id PRIMARY KEY DEFAULT gen_random_id(),    -- 분석 메트릭 레코드의 고유 식별자 (PK)
    snapshot_file_uuid id NOT NULL REFERENCES snapshot_file_instances(snapshot_file_uuid) ON DELETE CASCADE,
    -- 이 분석 메트릭의 대상이 되는 스냅샷 파일 인스턴스 (snapshot_file_instances.snapshot_file_uuid 참조)

    metric_type metric_type_enum NOT NULL,                   -- 파일 메타정보 또는 분석 메트릭의 종류
                                                             -- (00_repo_enums_and_types.sql 에 정의될 ENUM)
                                                             -- 예: 'LINES_OF_CODE', 'COMMENT_RATIO', 'RECENT_CHANGE_INTENSITY', 'DEPENDENCY_COUNT_INTERNAL', 'EXPORTED_ELEMENT_COUNT'
    metric_value_numeric NUMERIC,                            -- 메트릭 값이 숫자인 경우 (예: 250, 0.35, 5)
    metric_value_text TEXT,                                  -- 메트릭 값이 텍스트인 경우 (예: 'High Change Activity', 'No External Dependencies')
    metric_value_json JSONB,                                 -- 메트릭 값이 복잡한 구조(객체 또는 배열)인 경우 JSONB로 저장
                                                             -- 예: {"imported_modules": ["os", "sys"], "exported_functions": ["func_a", "func_b"]}

    analyzed_by_tool_name TEXT NOT NULL,                     -- 이 분석을 수행한 도구 또는 내부 로직의 이름 (예: 'ComfortCommit_FileStat_Analyzer', 'ComfortCommit_Dep_Counter_v1', 'cloc', 'git_blame_analyzer')
    analysis_tool_version TEXT,                              -- 사용된 분석 도구/로직의 버전 (선택적)
    analysis_timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP, -- 분석이 수행되고 이 메트릭이 기록된 시각

    -- 스케일업 시 고려:
    -- metric_unit TEXT,                                    -- metric_value_numeric의 단위 (예: 'lines', '%', 'count')
    -- is_llm_input_relevant BOOLEAN DEFAULT TRUE,          -- 이 메트릭이 LLM 입력 컨텍스트로 사용될 수 있는지 여부

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP, -- 이 메트릭 레코드가 DB에 생성된 시각
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP  -- 이 레코드 정보가 마지막으로 수정된 시각 (트리거로 자동 관리)
);

COMMENT ON TABLE file_analysis_metrics IS '특정 스냅샷의 각 파일 인스턴스에 대한 파일 메타정보 및 작업 흐름도 관련 분석 결과를 저장합니다. LLM 입력 컨텍스트로 활용될 수 있습니다.';
COMMENT ON COLUMN file_analysis_metrics.metric_uuid IS '각 파일 분석 메트릭 레코드의 고유 id입니다.';
COMMENT ON COLUMN file_analysis_metrics.snapshot_file_uuid IS '이 분석 메트릭의 대상이 되는 snapshot_file_instances 테이블의 파일 인스턴스 id입니다.';
COMMENT ON COLUMN file_analysis_metrics.metric_type IS '파일 메타정보 또는 분석된 메트릭의 종류를 나타냅니다 (00_repo_enums_and_types.sql에 정의된 metric_type_enum 값).';
COMMENT ON COLUMN file_analysis_metrics.metric_value_numeric IS '메트릭 결과가 숫자 형태일 경우 그 값을 저장합니다.';
COMMENT ON COLUMN file_analysis_metrics.metric_value_text IS '메트릭 결과가 단순 텍스트 형태일 경우 그 값을 저장합니다.';
COMMENT ON COLUMN file_analysis_metrics.metric_value_json IS '메트릭 결과가 복잡한 JSON 구조(객체 또는 배열)일 경우 그 값을 저장합니다. 예를 들어, 파일 내 import/export 목록 등이 해당될 수 있습니다.';
COMMENT ON COLUMN file_analysis_metrics.analyzed_by_tool_name IS '해당 분석 메트릭을 생성한 분석 도구 또는 내부 로직의 이름입니다.';
COMMENT ON COLUMN file_analysis_metrics.analysis_tool_version IS '사용된 분석 도구 또는 로직의 버전 정보입니다.';
COMMENT ON COLUMN file_analysis_metrics.analysis_timestamp IS '이 분석 메트릭이 계산되고 시스템에 기록된 시각입니다.';
COMMENT ON COLUMN file_analysis_metrics.created_at IS '이 메트릭 레코드가 데이터베이스에 생성된 시각입니다.';
COMMENT ON COLUMN file_analysis_metrics.updated_at IS '이 분석 메트릭 정보가 마지막으로 수정된 시각입니다.';


-- 인덱스
CREATE INDEX uuidx_file_analysis_metrics_snapshot_file_type ON file_analysis_metrics(snapshot_file_uuid, metric_type); -- 특정 파일의 특정 메트릭 타입 조회
CREATE INDEX uuidx_file_analysis_metrics_type_tool ON file_analysis_metrics(metric_type, analyzed_by_tool_name); -- 특정 메트릭 타입 및 도구로 분석된 모든 파일 조회
CREATE INDEX uuidx_file_analysis_metrics_analysis_timestamp ON file_analysis_metrics(analysis_timestamp DESC); -- 최근 분석된 메트릭 조회

-- updated_at 컬럼 자동 갱신 트리거 (00_common_functions_and_types.sql 에 set_updated_at 함수 정의 가정)
CREATE TRIGGER trg_set_updated_at_file_analysis_metrics
BEFORE UPDATE ON file_analysis_metrics
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- (00_repo_enums_and_types.sql 에 정의될 ENUM 예시 - "파일 메타정보" 및 "작업 흐름도 정보" 중심으로 수정)
-- CREATE TYPE metric_type_enum AS ENUM (
--     'LINES_OF_CODE_TOTAL',          -- 전체 라인 수
--     'LINES_OF_CODE_CODE',           -- 실제 코드 라인 수 (주석, 공백 제외)
--     'LINES_OF_CODE_COMMENT',        -- 주석 라인 수
--     'COMMENT_RATIO',                -- 주석 비율 (COMMENT / TOTAL)
--     'FILE_SIZE_BYTES',              -- 파일 크기 (바이트)
--     'RECENT_CHANGE_INTENSITY_SCORE',-- 최근 변경 강도 점수 (예: 최근 N일간 변경된 라인 수, 커밋 빈도 등 종합)
--     'DEPENDENCY_COUNT_INTERNAL',    -- 내부 모듈(파일) 의존성 개수
--     'DEPENDENCY_COUNT_EXTERNAL',    -- 외부 라이브러리 의존성 개수
--     'IMPORTED_MODULE_LIST_JSON',    -- import된 모듈 목록 (JSONB)
--     'EXPORTED_ELEMENT_COUNT',       -- 외부로 노출되는 함수/클래스 등의 개수
--     'FUNCTION_COUNT',               -- 파일 내 함수 개수
--     'CLASS_COUNT',                  -- 파일 내 클래스 개수
--     'LAST_MODIFIED_BY_AUTHOR',      -- 마지막 수정자 (git blame 정보 활용)
--     'FILE_AGE_DAYS',                -- 파일 생성 후 경과 일수
--     'LAST_COMMIT_TIMESTAMP',        -- 이 파일이 마지막으로 변경된 커밋의 타임스탬프
--     'OWNERSHIP_PERCENTAGE_TOP_DEV'  -- 주요 기여자(Top1)의 코드 소유권 비율 (git blame 기반)
--     -- 기타 개발자 작업 흐름 및 파일 상태 이해에 도움이 되는 메트릭 추가
-- );

-- =====================================================================================
-- 파일: 01_code_element_uuidentities.sql
-- 모듈: 04_repo_module / 04_code_elements (함수/클래스 등 코드 요소 단위 정보)
-- 설명: 저장소 내에서 고유하게 식별될 수 있는 코드 요소(함수, 클래스, 인터페이스, 주요 변수 등)의
--       "정체성" 또는 "원형(archetype)"을 정의합니다.
--       이 테이블은 특정 시점의 코드 인스턴스가 아닌, 코드 요소 자체의 고유한 식별 정보를 관리합니다.
--       예를 들어, 파일 위치가 변경되거나 시그니처가 약간 수정되어도 동일한 로직을 수행하는
--       함수/클래스임을 나타낼 수 있는 추상적인 uuid를 제공하는 것을 목표로 합니다.
-- 대상 DB: PostgreSQL Primary RDB
-- 파티셔닝: 해당 없음 (코드 요소 정의 마스터 성격)
-- MVP 중점사항: 코드 요소의 고유 uuid, 리포지토리 내 고유 경로/이름, 타입(함수/클래스 등), 최초 발견 시점.
-- 스케일업 고려사항: RLS, 코드 요소의 의미론적 해시값(Semantic Hashing) 저장, 버전 관리 개념 도입.
-- =====================================================================================

CREATE TABLE code_element_uuidentities (
    element_uuidentity_id id PRIMARY KEY DEFAULT gen_random_id(), -- 코드 요소 정체성의 고유 식별자 (PK)

    repo_id id NOT NULL REFERENCES repositories(repo_id) ON DELETE CASCADE,
    -- 이 코드 요소가 속한 저장소 (repositories.repo_id 참조)

    element_type code_element_type_enum NOT NULL,    -- 코드 요소의 타입 (예: 'FUNCTION', 'CLASS', 'INTERFACE', 'METHOD', 'MODULE_VARIABLE')
                                                      -- (00_repo_enums_and_types.sql 에 정의될 ENUM)

    -- 코드 요소를 고유하게 식별할 수 있는 정보 조합 (리포지토리 내에서 유일해야 함)
    -- 이 조합은 코드 분석 도구나 내부 로직을 통해 결정됩니다.
    -- 예: "파일경로::클래스명::메서드명(시그니처해시)" 또는 "모듈경로::함수명" 등
    -- MVP에서는 단순 이름/경로 기반으로 시작하고, 스케일업 시 시그니처 해시 등 추가 고려
    element_uuidentifier TEXT NOT NULL,
    -- 예시:
    --  - 'src/utils/helpers.py::calculate_sum' (함수)
    --  - 'src/models/user_model.py::User' (클래스)
    --  - 'src/services/auth_service.ts::AuthService::login' (클래스 내 메서드)
    --  - 'config/settings.ini::MAX_RETRIES' (설정 파일 내 주요 변수)

    element_name TEXT NOT NULL,                       -- 코드 요소의 이름 (예: 'calculate_sum', 'User', 'login')
    element_namespace TEXT,                           -- 코드 요소가 속한 네임스페이스 또는 모듈 경로 (선택적, element_uuidentifier 와 중복될 수 있음)
                                                      -- 예: 'src.utils.helpers', 'src.models.user_model'

    -- 코드 요소에 대한 간략한 설명 또는 주석 (파싱 가능할 경우)
    short_description TEXT,

    -- 이 코드 요소 정체성이 시스템에 처음으로 인식된 시점
    first_uuidentified_snapshot_uuid id REFERENCES code_snapshots(snapshot_uuid) ON DELETE SET NULL,
    -- 최초 발견된 스냅샷 uuid (code_snapshots.snapshot_uuid 참조), 스냅샷 삭제 시 연결만 해제

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

    -- 리포지토리 내에서 element_uuidentifier는 고유해야 함
    CONSTRAINT uq_code_element_uuidentities_repo_uuidentifier UNIQUE (repo_id, element_uuidentifier)
);

COMMENT ON TABLE code_element_uuidentities IS '저장소 내에서 고유하게 식별될 수 있는 코드 요소(함수, 클래스 등)의 추상적인 정체성(원형)을 정의합니다.';
COMMENT ON COLUMN code_element_uuidentities.element_uuidentity_id IS '코드 요소 정체성의 고유 id입니다.';
COMMENT ON COLUMN code_element_uuidentities.repo_id IS '이 코드 요소가 속한 저장소의 id (repositories.repo_id 참조)입니다.';
COMMENT ON COLUMN code_element_uuidentities.element_type IS '코드 요소의 타입을 나타냅니다 (00_repo_enums_and_types.sql에 정의된 code_element_type_enum 값).';
COMMENT ON COLUMN code_element_uuidentities.element_uuidentifier IS '리포지토리 내에서 해당 코드 요소를 고유하게 식별하는 문자열입니다. (예: "파일경로::클래스명::메서드명").';
COMMENT ON COLUMN code_element_uuidentities.element_name IS '코드 요소의 이름입니다 (예: 함수명, 클래스명).';
COMMENT ON COLUMN code_element_uuidentities.element_namespace IS '코드 요소가 속한 네임스페이스 또는 모듈 경로입니다.';
COMMENT ON COLUMN code_element_uuidentities.short_description IS '코드 요소에 대한 간략한 설명 또는 주석에서 추출한 내용입니다.';
COMMENT ON COLUMN code_element_uuidentities.first_uuidentified_snapshot_uuid IS '이 코드 요소의 정체성이 시스템에 처음으로 인식되었을 때의 스냅샷 uuid입니다.';
COMMENT ON COLUMN code_element_uuidentities.initial_definition_created_at IS '이 코드 요소의 "원형" 정의가 처음으로 기록된 시각입니다.';
COMMENT ON COLUMN code_element_uuidentities.tags IS '코드 요소를 분류하거나 검색하기 위한 추가적인 태그 또는 레이블 (JSONB)입니다.';
COMMENT ON CONSTRAINT uq_code_element_uuidentities_repo_uuidentifier ON code_element_uuidentities IS '하나의 저장소 내에서 element_uuidentifier는 고유해야 합니다.';


-- 인덱스
CREATE INDEX uuidx_code_element_uuidentities_repo_type ON code_element_uuidentities(repo_id, element_type);
CREATE INDEX uuidx_code_element_uuidentities_name ON code_element_uuidentities(element_name); -- 이름으로 검색 시
CREATE INDEX uuidx_code_element_uuidentities_tags_gin ON code_element_uuidentities USING GIN(tags); -- 태그 검색 시

-- updated_at 컬럼 자동 갱신 트리거 (00_common_functions_and_types.sql 에 set_updated_at 함수 정의 가정)
CREATE TRIGGER trg_set_updated_at_code_element_uuidentities
BEFORE UPDATE ON code_element_uuidentities
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

-- =====================================================================================
-- 파일: 02_snapshot_code_element_instances.sql
-- 모듈: 04_repo_module / 04_code_elements (함수/클래스 등 코드 요소 단위 정보)
-- 설명: 'code_element_uuidentities'에서 정의된 코드 요소의 "정체성"이 특정 스냅샷 시점에서
--       어떤 실제 내용과 속성(예: 라인 수, 실제 코드 조각, 시그니처 등)을 가지고 있는지를 기록합니다.
--       이 테이블의 레코드는 LLM 호출 시 분석 대상이 되는 구체적인 코드 요소의 "실체"입니다.
-- 대상 DB: PostgreSQL Primary RDB
-- 파티셔닝: 고려 가능 (snapshot_uuid 기준으로, 매우 많은 스냅샷과 코드 요소 인스턴스가 발생할 경우)
-- =====================================================================================

CREATE TABLE snapshot_code_element_instances (
    element_instance_id id PRIMARY KEY DEFAULT gen_random_id(),

    element_uuidentity_id id NOT NULL 
        REFERENCES code_element_uuidentities(element_uuidentity_id) ON DELETE CASCADE,

    snapshot_file_uuid id NOT NULL 
        REFERENCES snapshot_file_instances(snapshot_file_uuid) ON DELETE CASCADE,

    start_line_number INT NOT NULL,
    end_line_number INT NOT NULL,
    start_column_number INT,
    end_column_number INT,

    instance_name TEXT NOT NULL,
    instance_signature TEXT,

    code_content_snippet TEXT,

    metadata JSONB DEFAULT '{}'::JSONB,

    previous_element_instance_id id 
        REFERENCES snapshot_code_element_instances(element_instance_id) ON DELETE SET NULL,
    -- 이 인스턴스가 리팩토링, 변경 등으로 이어진 이전 코드 인스턴스를 참조합니다.

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_snapshot_element_uuidentity 
        UNIQUE (snapshot_file_uuid, element_uuidentity_id)
);

COMMENT ON TABLE snapshot_code_element_instances IS '특정 시점에서 존재하는 각 코드 요소 인스턴스의 실체를 저장하는 테이블입니다.';
COMMENT ON COLUMN snapshot_code_element_instances.previous_element_instance_id IS '이 인스턴스가 어떤 이전 인스턴스를 기반으로 생성되었는지 나타냅니다. 리팩토링 흐름 추적에 사용됩니다.';
COMMENT ON CONSTRAINT uq_snapshot_element_uuidentity ON snapshot_code_element_instances IS '동일 스냅샷 파일 내에서 동일한 정체성의 코드 요소 인스턴스는 유일해야 합니다.';

-- 인덱스
CREATE INDEX uuidx_snapshot_code_element_instances_uuidentity_snapshot 
    ON snapshot_code_element_instances(element_uuidentity_id, snapshot_file_uuid);

CREATE INDEX uuidx_snapshot_code_element_instances_snapshot_file_uuid 
    ON snapshot_code_element_instances(snapshot_file_uuid);

CREATE INDEX uuidx_snapshot_code_element_instances_instance_name 
    ON snapshot_code_element_instances(instance_name);

CREATE INDEX uuidx_snapshot_code_element_instances_prev 
    ON snapshot_code_element_instances(previous_element_instance_id);

-- updated_at 자동 갱신 트리거
CREATE TRIGGER trg_set_updated_at_snapshot_code_element_instances
BEFORE UPDATE ON snapshot_code_element_instances
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =====================================================================================
-- 파일: 03_code_element_relations.sql
-- 모듈: 04_repo_module / 04_code_elements (함수/클래스 등 코드 요소 단위 정보)
-- 설명: 특정 스냅샷 시점에서 코드 요소 인스턴스들 간의 관계(예: 호출, 사용, 의존, 상속 등)를 정의합니다.
--       이 정보는 코드 요소 간의 연결성을 파악하고, 변경의 영향을 분석하며,
--       유사도 기반 스코핑의 입력 데이터로 활용될 수 있습니다.
-- 대상 DB: PostgreSQL Primary RDB
-- 파티셔닝: 고려 가능 (snapshot_uuid 또는 관계 분석 시점 기준으로, 관계 데이터가 매우 많을 경우)
-- MVP 중점사항: 소스-타겟 요소 관계, 관계 타입(ENUM), 분석 방법, (선택적) 관계 강도/확신도.
-- 스케일업 고려사항: RLS, 파티셔닝, 관계의 세부 속성(예: 호출 시 파라미터 정보), 순환 참조 감지 플래그.
-- =====================================================================================

CREATE TABLE code_element_relations (
    relation_uuid id PRIMARY KEY DEFAULT gen_random_id(), -- 관계 레코드의 고유 식별자 (PK)

    snapshot_uuid id NOT NULL REFERENCES code_snapshots(snapshot_uuid) ON DELETE CASCADE,
    -- 이 관계가 분석된 시점의 스냅샷 (code_snapshots.snapshot_uuid 참조)
    -- 스냅샷이 삭제되면 해당 스냅샷에서 분석된 관계 정보도 함께 삭제

    source_element_instance_id id NOT NULL REFERENCES snapshot_code_element_instances(element_instance_id) ON DELETE CASCADE,
    -- 관계의 출발점이 되는 코드 요소 인스턴스
    -- (snapshot_code_element_instances.element_instance_id 참조)

    target_element_instance_id id NOT NULL REFERENCES snapshot_code_element_instances(element_instance_id) ON DELETE CASCADE,
    -- 관계의 대상이 되는 코드 요소 인스턴스
    -- (snapshot_code_element_instances.element_instance_id 참조)

    relation_type element_relation_type_enum NOT NULL, -- 관계의 유형 (예: 'CALLS', 'USES_VARIABLE', 'IMPORTS_MODULE', 'INHERITS_FROM', 'IMPLEMENTS_INTERFACE', 'REFERENCES_TYPE')
                                                       -- (00_repo_enums_and_types.sql 에 정의될 ENUM)

    -- 관계가 설정된 구체적인 위치 정보 (선택적, 소스 코드 내)
    source_relation_start_line INT,
    source_relation_end_line INT,
    source_relation_start_column INT,
    source_relation_end_column INT,

    -- 이 관계가 어떻게 분석되었는지에 대한 정보
    analysis_method TEXT,                             -- 예: 'STATIC_IMPORT_ANALYSIS', 'CALL_GRAPH_GENERATION', 'AST_WALK', 'USER_DEFINED'
    confuuidence_score NUMERIC(5,4),                    -- 이 관계 분석 결과에 대한 확신도 (0.0 ~ 1.0, 선택적)

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
    CONSTRAINT uq_code_element_relation_snapshot_source_target_type UNIQUE (snapshot_uuid, source_element_instance_id, target_element_instance_id, relation_type)
);

COMMENT ON TABLE code_element_relations IS '특정 스냅샷 시점에서 코드 요소 인스턴스들 간의 관계(호출, 의존 등)를 기록합니다.';
COMMENT ON COLUMN code_element_relations.relation_uuid IS '관계 레코드의 고유 id입니다.';
COMMENT ON COLUMN code_element_relations.snapshot_uuid IS '이 관계가 분석된 시점의 스냅샷 id (code_snapshots.snapshot_uuid 참조)입니다.';
COMMENT ON COLUMN code_element_relations.source_element_instance_id IS '관계의 시작점(호출하는 쪽, 의존하는 쪽 등)이 되는 코드 요소 인스턴스의 id입니다.';
COMMENT ON COLUMN code_element_relations.target_element_instance_id IS '관계의 대상(호출되는 쪽, 의존되는 쪽 등)이 되는 코드 요소 인스턴스의 id입니다.';
COMMENT ON COLUMN code_element_relations.relation_type IS '코드 요소 간의 관계 유형을 나타냅니다 (00_repo_enums_and_types.sql에 정의된 element_relation_type_enum 값).';
COMMENT ON COLUMN code_element_relations.source_relation_start_line IS '소스 코드 요소 내에서 이 관계가 시작되는 라인 번호입니다 (선택적).';
COMMENT ON COLUMN code_element_relations.source_relation_end_line IS '소스 코드 요소 내에서 이 관계가 끝나는 라인 번호입니다 (선택적).';
COMMENT ON COLUMN code_element_relations.analysis_method IS '이 관계를 분석하거나 식별하는 데 사용된 방법 또는 도구의 이름입니다.';
COMMENT ON COLUMN code_element_relations.confuuidence_score IS '분석된 관계의 정확성에 대한 확신도 점수입니다 (0.0 ~ 1.0).';
COMMENT ON COLUMN code_element_relations.properties IS '관계에 대한 추가적인 속성 정보를 JSONB 형태로 저장합니다 (예: 호출 인자 정보).';
COMMENT ON CONSTRAINT uq_code_element_relation_snapshot_source_target_type ON code_element_relations IS '동일 스냅샷 내에서 두 코드 요소 인스턴스 간에 동일한 타입의 관계는 유일해야 합니다.';


-- 인덱스
CREATE INDEX uuidx_code_element_relations_snapshot_source ON code_element_relations(snapshot_uuid, source_element_instance_id);
CREATE INDEX uuidx_code_element_relations_snapshot_target ON code_element_relations(snapshot_uuid, target_element_instance_id);
CREATE INDEX uuidx_code_element_relations_relation_type ON code_element_relations(relation_type);
CREATE INDEX uuidx_code_element_relations_analysis_method ON code_element_relations(analysis_method);

-- 복합 인덱스 (특정 요소의 모든 관계 조회 시 유용)
CREATE INDEX uuidx_code_element_relations_source_or_target ON code_element_relations USING GIN (ARRAY[source_element_instance_id, target_element_instance_id]);


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

-- =====================================================================================
-- 파일: 04_code_element_embeddings.sql
-- 모듈: 04_repo_module / 04_code_elements (함수/클래스 등 코드 요소 단위 정보)
-- 설명: 특정 스냅샷 시점의 코드 요소 인스턴스에 대해 계산된 임베딩 벡터와,
--       다른 코드 요소 인스턴스와의 계산된 유사도 점수를 저장합니다.
--       (예: Code2Vec, AST 기반 임베딩, Sentence-BERT 등 다양한 모델 활용 가능)
--       이 정보는 의미론적 유사도 기반 스코핑 및 관련 코드 추천 등에 활용됩니다.
-- 대상 DB: PostgreSQL Primary RDB (pgvector 확장 필요)
-- 파티셔닝: 고려 가능 (element_instance_id 또는 embedding_model_name 기준으로, 데이터가 매우 많을 경우)
-- MVP 중점사항: 코드 요소 인스턴스 참조, 임베딩 모델 정보, 벡터 값, (선택적) 주요 유사도 관계 기록.
-- 스케일업 고려사항: RLS, 파티셔닝, 다양한 임베딩 모델 지원, 근사 최근접 이웃(ANN) 검색 최적화.
-- =====================================================================================

-- pgvector 확장이 설치되어 있어야 `vector` 타입을 사용할 수 있습니다.
-- CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE code_element_embeddings (
    embedding_uuid id PRIMARY KEY DEFAULT gen_random_id(), -- 임베딩 레코드의 고유 식별자 (PK)

    element_instance_id id NOT NULL REFERENCES snapshot_code_element_instances(element_instance_id) ON DELETE CASCADE,
    -- 이 임베딩이 계산된 대상 코드 요소 인스턴스
    -- (snapshot_code_element_instances.element_instance_id 참조)

    embedding_model_name TEXT NOT NULL,        -- 사용된 임베딩 모델의 이름 (예: 'code2vec_cbow', 'sentence-bert-base-nli-mean-tokens', 'text-embedding-ada-002')
    embedding_model_version TEXT,              -- 사용된 임베딩 모델의 버전 (선택적)
    vector_dimensions INT NOT NULL,            -- 임베딩 벡터의 차원 수 (예: 128, 768, 1536)

    embedding_vector VECTOR,             -- 실제 임베딩 벡터 값 (pgvector 타입 사용, 차원 수는 최대값 기준으로 설정 후 모델별로 조절)
                                               -- 차원 수는 가장 큰 모델 기준으로 설정하고, 작은 차원의 벡터는 패딩하거나 별도 컬럼/테이블로 관리 가능.
                                               -- 또는 모델별로 테이블을 분리하거나, JSONB에 저장하는 방식도 고려 가능 (검색 성능에 영향).
                                               -- MVP에서는 일단 최대 차원수 하나로 통일하고, 실제 사용 시 모델별 최적화.

    -- (선택적) 이 임베딩과 가장 유사한 Top-N개의 다른 코드 요소 인스턴스와의 유사도 점수 저장
    -- 이는 스코핑 결과 테이블(05_commit_generation/04_scoping_results.sql)로 이동하거나 중복 저장될 수 있음.
    -- 또는 자주 사용되는 유사도 쌍을 캐시하는 용도로 활용 가능.
    -- top_n_similar_elements JSONB,
    -- 예: [
    --   {"target_element_instance_id": "id_xyz", "similarity_score": 0.95, "rank": 1},
    --   {"target_element_instance_id": "id_abc", "similarity_score": 0.92, "rank": 2}
    -- ]

    -- 임베딩 계산에 사용된 소스 코드의 해시값 (내용 변경 시 재계산 여부 판단용, 선택적)
    source_code_checksum TEXT,

    --  auditing
    generated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, -- 임베딩이 생성된 시각
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE code_element_embeddings IS '특정 스냅샷 시점의 코드 요소 인스턴스에 대한 임베딩 벡터 및 관련 정보를 저장합니다.';
COMMENT ON COLUMN code_element_embeddings.embedding_uuid IS '임베딩 레코드의 고유 id입니다.';
COMMENT ON COLUMN code_element_embeddings.element_instance_id IS '임베딩이 계산된 코드 요소 인스턴스의 id입니다.';
COMMENT ON COLUMN code_element_embeddings.embedding_model_name IS '임베딩 생성에 사용된 모델의 이름입니다.';
COMMENT ON COLUMN code_element_embeddings.embedding_model_version IS '사용된 임베딩 모델의 버전입니다.';
COMMENT ON COLUMN code_element_embeddings.vector_dimensions IS '임베딩 벡터의 차원 수입니다.';
COMMENT ON COLUMN code_element_embeddings.embedding_vector IS '계산된 실제 임베딩 벡터 값입니다 (pgvector 타입).';
-- COMMENT ON COLUMN code_element_embeddings.top_n_similar_elements IS '이 임베딩과 가장 유사한 Top-N 코드 요소 인스턴스 및 유사도 점수를 JSONB 형태로 저장합니다 (선택적).';
COMMENT ON COLUMN code_element_embeddings.source_code_checksum IS '임베딩 계산의 기반이 된 소스 코드의 체크섬입니다 (선택적).';
COMMENT ON COLUMN code_element_embeddings.generated_at IS '임베딩 벡터가 생성된 시각입니다.';


-- 인덱스
-- element_instance_id 와 model_name 조합으로 특정 인스턴스의 특정 모델 임베딩을 빠르게 조회
CREATE UNIQUE INDEX uq_uuidx_code_element_embeddings_instance_model ON code_element_embeddings(element_instance_id, embedding_model_name);

-- pgvector 사용 시 벡터 유사도 검색을 위한 HNSW 또는 IVFFlat 인덱스 (예시)
-- 실제 사용할 유사도 측정 방식(L2, inner product, cosine)과 데이터 분포에 따라 인덱스 타입 및 파라미터 결정 필요
-- CREATE INDEX uuidx_code_element_embeddings_vector_hnsw ON code_element_embeddings USING hnsw (embedding_vector vector_cosine_ops);
-- 참고: 위 HNSW 인덱스 예시는 코사인 유사도 기준입니다.

-- updated_at 컬럼 자동 갱신 트리거 (00_common_functions_and_types.sql 에 set_updated_at 함수 정의 가정)
CREATE TRIGGER trg_set_updated_at_code_element_embeddings
BEFORE UPDATE ON code_element_embeddings
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =====================================================================================
-- 파일: 01_commit_generation_requests.sql
-- 모듈: 04_repo_module / 05_commit_generation (LLM 기반 커밋 메시지 생성 흐름)
-- 설명: 사용자의 커밋 메시지 생성 요청의 시작점입니다. 이 테이블은 특정 요청에 사용된
--       모든 입력 컨텍스트 정보(예: 스냅샷, 분석 대상 파일/함수, 스코핑 결과, README 요약,
--       Diff 조각, 적용된 규칙 등)의 참조 uuid를 포함하며, 생성된 기술 설명서, 커밋 초안,
--       최종 확정 커밋까지 이어지는 전체 프로세스를 관리하는 중심 테이블입니다.
-- 대상 DB: PostgreSQL Primary RDB
-- 파티셔닝: 고려 가능 (request_timestamp 기준으로, 요청이 매우 많을 경우)
-- MVP 중점사항: 요청 식별자, 사용자/세션 정보, 원본 스냅샷, 주요 변경 파일, LLM 호출 단계별 상태, 최종 커밋 참조.
-- 스케일업 고려사항: RLS, 파티셔닝, 상세한 요청 파라미터 저장, 요청별 비용 추적 연동, 다양한 트리거 방식 지원.
-- =====================================================================================

CREATE TABLE commit_generation_requests (
    request_uuid id PRIMARY KEY DEFAULT gen_random_id(), -- 커밋 생성 요청의 고유 식별자 (PK)

    -- 요청자 및 세션 정보
    user_id id NOT NULL REFERENCES user_info(id) ON DELETE SET NULL, -- 요청한 사용자 (user_info.id 참조)
    session_uuid id REFERENCES user_session(session_uuid) ON DELETE SET NULL, -- 요청이 발생한 세션 (user_session.session_uuid 참조, 선택적)
    repo_id id NOT NULL REFERENCES repositories(repo_id) ON DELETE CASCADE, -- 대상 저장소 (repositories.repo_id 참조)

    -- 요청의 기준이 되는 스냅샷 정보
    source_snapshot_uuid id NOT NULL REFERENCES code_snapshots(snapshot_uuid) ON DELETE RESTRICT,
    -- 이 커밋 생성 요청의 분석 대상이 되는 원본 코드 스냅샷 (code_snapshots.snapshot_uuid 참조)
    -- ON DELETE RESTRICT: 커밋 생성 요청이 참조하는 스냅샷은 임의로 삭제할 수 없도록 제한

    -- 주요 변경 파일/요소 식별 정보 (스코핑 전 단계 또는 대표 변경 사항)
    -- 이 부분은 여러 파일/요소가 될 수 있으므로, 별도 매핑 테이블이나 JSONB로 관리 가능. MVP에서는 주요 파일 1개로 단순화 가능.
    primary_changed_file_instance_uuid id REFERENCES snapshot_file_instances(snapshot_file_uuid) ON DELETE SET NULL,
    -- 요청의 주된 분석 대상이 된 파일 인스턴스 (선택적, 스코핑 결과로 대체 가능)

    -- LLM 호출 및 생성 프로세스 상태 관리
    request_status request_status_enum DEFAULT 'PENDING', -- 현재 요청 처리 상태 (00_repo_enums_and_types.sql 에 정의될 ENUM)
                                                         -- 예: 'PENDING', 'SCOPING_STATIC', 'SCOPING_EMBEDDING', 'GENERATING_TECH_DESC', 'TECH_DESC_READY', 'GENERATING_COMMIT_MSG', 'COMMIT_MSG_READY', 'USER_REVIEW', 'COMPLETED', 'FAILED', 'CANCELLED'
    error_message TEXT,                                  -- 오류 발생 시 메시지

    -- 1차 LLM 호출 (기술 설명서 생성) 관련 컨텍스트 참조 uuid
    -- 실제 스코핑 결과는 `scoping_results` 테이블에 저장되고, 이 테이블에서는 해당 결과셋 uuid를 참조할 수 있음.
    scoping_result_uuid id, -- REFERENCES scoping_results(scoping_run_uuid) ON DELETE SET NULL, (04_scoping_results.sql 정의 후 FK 설정)
                            -- 1, 2차 스코핑 결과로 확정된 분석 대상 함수/파일 목록 세트 uuid

    readme_content_uuid id, -- REFERENCES generated_contents(content_uuid) ON DELETE SET NULL, (README 요약본 저장 테이블 참조)
                            -- 사용된 README 요약본의 uuid (별도 콘텐츠 관리 테이블 필요 시) 또는 직접 저장 (아래 `context_references_json`)

    -- 2차 LLM 호출 (커밋 메시지 생성) 관련 컨텍스트 참조 uuid
    -- 생성된 기술 설명서는 `generated_tech_description` 테이블에 저장되고, 여기서는 주요 설명서 uuid 목록을 참조.
    -- 사용된 Diff 조각은 `file_diff_fragments` 테이블에 저장되고, 여기서는 주요 Diff 조각 uuid 목록을 참조.
    context_references_json JSONB,
    -- 예: {
    --   "technical_description_uuids": ["id1", "id2"], (05_generated_tech_description.sql 참조)
    --   "diff_fragment_uuids": ["id_a", "id_b"], (02_code_snapshots/03_file_diff_fragments.sql 참조)
    --   "file_analysis_metric_uuids_for_llm": ["metric_id_x"], (03_files/03_file_analysis_metrics.sql 참조)
    --   "relevant_code_element_relation_uuids": ["relation_id_y"], (04_code_elements/03_code_element_relations.sql 참조)
    --   "custom_commit_rule_uuid": "rule_id_z", (05_customization_and_rules_module 참조)
    --   "applied_commit_template_uuid": "template_id_k" (template/ 내부 파일 또는 DB화된 템플릿 uuid)
    -- }

    -- 최종 결과물 참조
    generated_commit_content_uuid id, -- REFERENCES generated_commit_contents(generated_content_uuid) ON DELETE SET NULL, (02_generated_commit_contents.sql 정의 후 FK 설정)
                                      -- LLM이 생성한 커밋 메시지 초안의 uuid
    finalized_commit_uuid id,         -- REFERENCES finalized_commits(finalized_commit_id) ON DELETE SET NULL, (03_finalized_commits.sql 정의 후 FK 설정)
                                      -- 사용자가 최종 확정한 커밋의 uuid

    -- 요청 및 완료 시각
    request_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, -- 요청이 시스템에 접수된 시각
    completion_timestamp TIMESTAMP WITH TIME ZONE,                        -- 모든 처리가 완료된 시각

    -- 추가 설정 및 메타데이터
    user_preferences_json JSONB,      -- 요청 시 사용자의 특정 선호도 설정 (예: 커밋 스타일, 언어 등)
    processing_metadata JSONB,        -- 처리 과정 중 발생한 메타데이터 (예: 각 단계별 소요 시간, 사용된 LLM 모델 정보 등)

    --  auditing
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE commit_generation_requests IS '사용자의 커밋 메시지 생성 요청의 시작점 및 전체 프로세스 관리 허브입니다.';
COMMENT ON COLUMN commit_generation_requests.request_uuid IS '커밋 생성 요청의 고유 id입니다.';
COMMENT ON COLUMN commit_generation_requests.user_id IS '요청을 시작한 사용자의 id입니다.';
COMMENT ON COLUMN commit_generation_requests.repo_id IS '커밋 생성 대상 저장소의 id입니다.';
COMMENT ON COLUMN commit_generation_requests.source_snapshot_uuid IS '분석의 기준이 되는 코드 스냅샷의 id입니다.';
COMMENT ON COLUMN commit_generation_requests.primary_changed_file_instance_uuid IS '요청의 주된 분석 대상이 된 파일 인스턴스의 id (선택적)입니다.';
COMMENT ON COLUMN commit_generation_requests.request_status IS '현재 커밋 생성 요청의 처리 상태입니다 (00_repo_enums_and_types.sql에 정의된 request_status_enum 값).';
COMMENT ON COLUMN commit_generation_requests.scoping_result_uuid IS '이 요청에 사용된 스코핑 결과 세트의 uuid 참조입니다 (04_scoping_results.sql 테이블 정의 후 FK 설정).';
COMMENT ON COLUMN commit_generation_requests.readme_content_uuid IS 'LLM 입력에 사용된 README 요약본의 uuid 참조입니다 (별도 콘텐츠 관리 테이블 필요 시).';
COMMENT ON COLUMN commit_generation_requests.context_references_json IS '커밋 메시지 생성(2차 LLM 호출)에 사용된 다양한 컨텍스트 요소들의 참조 uuid를 JSONB 형태로 저장합니다.';
COMMENT ON COLUMN commit_generation_requests.generated_commit_content_uuid IS 'LLM이 생성한 커밋 메시지 초안의 uuid 참조입니다 (02_generated_commit_contents.sql 테이블 정의 후 FK 설정).';
COMMENT ON COLUMN commit_generation_requests.finalized_commit_uuid IS '사용자가 최종 확정한 커밋의 uuid 참조입니다 (03_finalized_commits.sql 테이블 정의 후 FK 설정).';
COMMENT ON COLUMN commit_generation_requests.request_timestamp IS '요청이 시스템에 접수된 시각입니다.';
COMMENT ON COLUMN commit_generation_requests.completion_timestamp IS '요청 처리가 최종적으로 완료된 시각입니다.';
COMMENT ON COLUMN commit_generation_requests.user_preferences_json IS '요청 시 적용된 사용자 선호도 설정 (커밋 스타일, 언어 등)입니다.';
COMMENT ON COLUMN commit_generation_requests.processing_metadata IS '요청 처리 과정에서 발생한 내부 메타데이터 (단계별 소요 시간, 사용 모델 등)입니다.';


-- 인덱스
CREATE INDEX uuidx_cgr_user_repo_status ON commit_generation_requests(user_id, repo_id, request_status);
CREATE INDEX uuidx_cgr_request_timestamp ON commit_generation_requests(request_timestamp DESC);
CREATE INDEX uuidx_cgr_status_timestamp ON commit_generation_requests(request_status, request_timestamp DESC);
CREATE INDEX uuidx_cgr_source_snapshot_uuid ON commit_generation_requests(source_snapshot_uuid);

-- FK 제약조건은 참조하는 테이블들이 먼저 생성된 후 ALTER TABLE로 추가하는 것을 권장 (순환 참조 방지 및 관리 용이성)
-- 예:
-- ALTER TABLE commit_generation_requests ADD CONSTRAINT fk_cgr_scoping_result FOREIGN KEY (scoping_result_uuid) REFERENCES scoping_results(scoping_run_uuid) ON DELETE SET NULL;
-- ALTER TABLE commit_generation_requests ADD CONSTRAINT fk_cgr_generated_content FOREIGN KEY (generated_commit_content_uuid) REFERENCES generated_commit_contents(generated_content_uuid) ON DELETE SET NULL;
-- ALTER TABLE commit_generation_requests ADD CONSTRAINT fk_cgr_finalized_commit FOREIGN KEY (finalized_commit_uuid) REFERENCES finalized_commits(finalized_commit_id) ON DELETE SET NULL;


-- updated_at 컬럼 자동 갱신 트리거 (00_common_functions_and_types.sql 에 set_updated_at 함수 정의 가정)
CREATE TRIGGER trg_set_updated_at_commit_generation_requests
BEFORE UPDATE ON commit_generation_requests
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- (00_repo_enums_and_types.sql 에 정의될 ENUM 예시)
-- CREATE TYPE request_status_enum AS ENUM (
--     'PENDING',                    -- 요청 접수, 처리 대기 중
--     'PREPROCESSING_FILES',        -- 파일 정보 수집 및 기본 분석 중
--     'SCOPING_STATIC_ANALYSIS',    -- 정적 분석 기반 스코핑 진행 중
--     'SCOPING_EMBEDDING_ANALYSIS', -- 임베딩 기반 스코핑 진행 중
--     'SCOPING_COMPLETED',          -- 스코핑 완료, 기술 설명서 생성 대기
--     'GENERATING_TECH_DESCRIPTION',-- 1차 LLM 호출: 기술 설명서 생성 중
--     'TECH_DESCRIPTION_READY',     -- 기술 설명서 생성 완료, 커밋 메시지 생성 대기
--     'GENERATING_COMMIT_MESSAGE',  -- 2차 LLM 호출: 커밋 메시지 생성 중
--     'COMMIT_MESSAGE_READY',       -- 커밋 메시지 초안 생성 완료, 사용자 검토 대기
--     'AWAITING_USER_REVIEW',       -- 사용자 검토 대기 중 (웹/모바일 인터페이스)
--     'USER_APPROVED',              -- 사용자가 승인함
--     'USER_EDITED_AND_APPROVED',   -- 사용자가 수정 후 승인함
--     'AUTO_COMMITTED',             -- (정책에 따라) 자동 커밋됨
--     'COMPLETED_SUCCESS',          -- 모든 처리 성공적으로 완료
--     'FAILED_PREPROCESSING',
--     'FAILED_SCOPING',
--     'FAILED_LLM_TECH_DESC',
--     'FAILED_LLM_COMMIT_MSG',
--     'FAILED_GIT_COMMIT',
--     'CANCELLED_BY_USER',
--     'TIMED_OUT'
-- );

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
    llm_request_log_uuid id, -- REFERENCES llm_request_log(uuid) ON DELETE SET NULL, (02_llm_module/02_llm_request_log.sql 참조)
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
COMMENT ON COLUMN generated_commit_contents.llm_generation_parameters IS 'LLM 호출 시 사용된 주요 생성 파라미터 (temperature, top_p 등)를 JSONB 형태로 저장합니다.';
COMMENT ON COLUMN generated_commit_contents.llm_request_log_uuid IS '실제 LLM API 호출에 대한 로그 uuid (llm_request_log.uuid 참조)입니다. 토큰 사용량, 비용 등의 상세 정보 추적에 사용됩니다.';
COMMENT ON COLUMN generated_commit_contents.llm_output_raw IS 'LLM으로부터 받은 응답의 원본 JSON 전체입니다 (디버깅 및 상세 분석용, 선택적).';
COMMENT ON COLUMN generated_commit_contents.generation_timestamp IS '커밋 메시지 초안이 LLM에 의해 생성된 시각입니다.';
COMMENT ON COLUMN generated_commit_contents.is_edited_by_user IS '이 LLM 생성 초안이 사용자에 의해 수정되었는지 여부를 나타냅니다 (최초 생성 시 FALSE).';
COMMENT ON COLUMN generated_commit_contents.user_feedback_score IS '생성된 커밋 메시지 초안에 대한 사용자의 만족도 점수입니다 (선택적).';
COMMENT ON COLUMN generated_commit_contents.user_feedback_notes IS '생성된 초안에 대한 사용자의 구체적인 피드백 코멘트입니다 (선택적).';


-- 인덱스
CREATE INDEX uuidx_gcc_request_uuid ON generated_commit_contents(request_uuid);
CREATE INDEX uuidx_gcc_llm_model_name ON generated_commit_contents(llm_model_name);
CREATE INDEX uuidx_gcc_generation_timestamp ON generated_commit_contents(generation_timestamp DESC);
CREATE INDEX uuidx_gcc_is_edited_by_user ON generated_commit_contents(is_edited_by_user);

-- FK 제약조건은 참조하는 테이블(llm_request_log)이 먼저 생성된 후 ALTER TABLE로 추가하는 것을 권장
-- ALTER TABLE generated_commit_contents ADD CONSTRAINT fk_gcc_llm_request_log FOREIGN KEY (llm_request_log_uuid) REFERENCES llm_request_log(uuid) ON DELETE SET NULL;


-- updated_at 컬럼 자동 갱신 트리거 (00_common_functions_and_types.sql 에 set_updated_at 함수 정의 가정)
CREATE TRIGGER trg_set_updated_at_generated_commit_contents
BEFORE UPDATE ON generated_commit_contents
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =====================================================================================
-- 파일: 03_finalized_commits.sql
-- 모듈: 04_repo_module / 05_commit_generation (LLM 기반 커밋 메시지 생성 흐름)
-- 설명: 사용자가 Comfort Commit 시스템을 통해 최종적으로 검토, 수정 및 확정한
--       커밋 메시지와 관련 승인 정보를 저장합니다. 이 정보는 실제 Git 커밋 실행의 기준이 되며,
--       사용자 행동 분석 및 시스템 감사에 활용됩니다.
-- 대상 DB: PostgreSQL Primary RDB
-- 파티셔닝: 고려 가능 (finalized_timestamp 기준으로, 데이터가 매우 많을 경우)
-- MVP 중점사항: 원본 요청/초안 참조, 최종 커밋 메시지, 승인자 정보, 승인 시각, 편집 여부.
-- 스케일업 고려사항: RLS, 파티셔닝, Git 커밋 해시(SHA) 저장, 푸시(push) 상태 추적, 다양한 승인 워크플로우 지원.
-- =====================================================================================

CREATE TABLE finalized_commits (
    finalized_commit_id id PRIMARY KEY DEFAULT gen_random_id(), -- 최종 확정된 커밋의 고유 식별자 (PK)

    request_uuid id NOT NULL REFERENCES commit_generation_requests(request_uuid) ON DELETE RESTRICT,
    -- 이 최종 커밋의 원본이 되는 커밋 생성 요청 (commit_generation_requests.request_uuid 참조)
    -- ON DELETE RESTRICT: 최종 확정된 커밋이 있는 요청은 임의로 삭제할 수 없도록 제한 (감사 추적)

    generated_content_uuid id NOT NULL REFERENCES generated_commit_contents(generated_content_uuid) ON DELETE RESTRICT,
    -- 사용자가 검토한 LLM 생성 커밋 메시지 초안 (generated_commit_contents.generated_content_uuid 참조)
    -- ON DELETE RESTRICT: 최종 확정된 커밋의 기반이 된 초안은 임의로 삭제할 수 없도록 제한

    -- 최종 확정된 커밋 메시지
    final_commit_message_title TEXT,
    final_commit_message_body TEXT,
    final_commit_message_full TEXT NOT NULL, -- 사용자가 최종 확정한 전체 커밋 메시지

    -- 승인자 및 승인 정보
    finalized_by_user_id id NOT NULL REFERENCES user_info(id) ON DELETE SET NULL,
    -- 이 커밋을 최종 확정한 사용자 (user_info.id 참조)
    finalized_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, -- 최종 확정 시각
    approval_source TEXT,                         -- 승인 경로/수단 (예: 'WEB_UI_APPROVAL', 'MOBILE_APP_SWIPE', 'SLACK_INTERACTION', 'AUTO_APPROVED_BY_RULE')

    was_edited_from_generated BOOLEAN NOT NULL DEFAULT FALSE, -- LLM 생성 초안에서 사용자에 의해 수정되었는지 여부
                                                          -- TRUE이면 generated_commit_contents.commit_message_full 과 다름.

    -- 실제 Git 커밋 관련 정보 (Git 커밋 실행 후 업데이트)
    git_commit_sha TEXT UNIQUE,                   -- 실제 Git 리포지토리에 커밋된 후 생성된 SHA-1 해시 (선택적, 커밋 후 업데이트)
                                                  -- UNIQUE 제약으로 동일 SHA 중복 방지
    git_commit_timestamp TIMESTAMP WITH TIME ZONE,  -- 실제 Git 커밋 시각 (선택적)
    git_push_status push_status_enum,             -- Git push 상태 (00_repo_enums_and_types.sql 에 정의될 ENUM, 선택적)
                                                  -- 예: 'NOT_PUSHED', 'PUSH_PENDING', 'PUSH_SUCCESSFUL', 'PUSH_FAILED'
    git_push_timestamp TIMESTAMP WITH TIME ZONE,    -- Git push 시각 (선택적)
    git_error_message TEXT,                       -- Git 작업(커밋/푸시) 실패 시 오류 메시지

    -- 추가 메타데이터
    review_notes TEXT,                            -- 최종 확정 과정에서의 사용자 또는 시스템 메모

    --  auditing
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE finalized_commits IS '사용자가 Comfort Commit을 통해 최종 검토 및 확정한 커밋 메시지와 관련 승인 정보를 저장합니다.';
COMMENT ON COLUMN finalized_commits.finalized_commit_id IS '최종 확정된 커밋의 고유 id입니다.';
COMMENT ON COLUMN finalized_commits.request_uuid IS '이 최종 커밋의 원본 커밋 생성 요청 id (commit_generation_requests.request_uuid 참조)입니다.';
COMMENT ON COLUMN finalized_commits.generated_content_uuid IS '사용자가 검토한 LLM 생성 커밋 메시지 초안의 id (generated_commit_contents.generated_content_uuid 참조)입니다.';
COMMENT ON COLUMN finalized_commits.final_commit_message_title IS '사용자가 최종 확정한 커밋 메시지의 제목 부분입니다.';
COMMENT ON COLUMN finalized_commits.final_commit_message_body IS '사용자가 최종 확정한 커밋 메시지의 본문 부분입니다.';
COMMENT ON COLUMN finalized_commits.final_commit_message_full IS '사용자가 최종 확정한 전체 커밋 메시지 텍스트입니다.';
COMMENT ON COLUMN finalized_commits.finalized_by_user_id IS '이 커밋을 최종 확정한 사용자의 id (user_info.id 참조)입니다.';
COMMENT ON COLUMN finalized_commits.finalized_timestamp IS '사용자가 커밋을 최종 확정한 시각입니다.';
COMMENT ON COLUMN finalized_commits.approval_source IS '커밋이 승인된 경로 또는 수단을 나타냅니다 (예: 웹 UI, 모바일 앱).';
COMMENT ON COLUMN finalized_commits.was_edited_from_generated IS 'LLM이 생성한 초안에서 사용자에 의해 내용이 수정되었는지 여부를 나타냅니다.';
COMMENT ON COLUMN finalized_commits.git_commit_sha IS '실제 Git 리포지토리에 반영된 커밋의 SHA-1 해시값입니다 (커밋 실행 후 업데이트).';
COMMENT ON COLUMN finalized_commits.git_commit_timestamp IS '실제 Git 커밋이 이루어진 시각입니다.';
COMMENT ON COLUMN finalized_commits.git_push_status IS '연결된 Git 리포지토리로의 push 상태입니다 (00_repo_enums_and_types.sql에 정의된 push_status_enum 값).';
COMMENT ON COLUMN finalized_commits.git_push_timestamp IS 'Git push가 이루어진 시각입니다.';
COMMENT ON COLUMN finalized_commits.git_error_message IS 'Git 커밋 또는 푸시 작업 중 오류 발생 시 해당 오류 메시지를 저장합니다.';
COMMENT ON COLUMN finalized_commits.review_notes IS '최종 확정 과정에 대한 추가적인 사용자 또는 시스템 메모입니다.';


-- 인덱스
CREATE INDEX uuidx_fc_request_uuid ON finalized_commits(request_uuid);
CREATE INDEX uuidx_fc_generated_content_uuid ON finalized_commits(generated_content_uuid);
CREATE INDEX uuidx_fc_finalized_by_user_id ON finalized_commits(finalized_by_user_id);
CREATE INDEX uuidx_fc_finalized_timestamp ON finalized_commits(finalized_timestamp DESC);
CREATE INDEX uuidx_fc_git_commit_sha ON finalized_commits(git_commit_sha) WHERE git_commit_sha IS NOT NULL;
CREATE INDEX uuidx_fc_git_push_status ON finalized_commits(git_push_status);

-- updated_at 컬럼 자동 갱신 트리거 (00_common_functions_and_types.sql 에 set_updated_at 함수 정의 가정)
CREATE TRIGGER trg_set_updated_at_finalized_commits
BEFORE UPDATE ON finalized_commits
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- (00_repo_enums_and_types.sql 에 정의될 ENUM 예시)
-- CREATE TYPE push_status_enum AS ENUM (
--     'NOT_PUSHED',       -- 아직 Push 되지 않음
--     'PUSH_PENDING',     -- Push 대기열에 있음
--     'PUSH_IN_PROGRESS', -- Push 진행 중
--     'PUSH_SUCCESSFUL',  -- Push 성공
--     'PUSH_FAILED',      -- Push 실패
--     'PUSH_PARTIAL'      -- 부분적으로 Push 성공 (일부 브랜치/태그 등)
-- );

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
COMMENT ON COLUMN scoping_results.request_uuid IS '이 스코핑 결과가 속한 커밋 생성 요청의 id입니다.';
COMMENT ON COLUMN scoping_results.scoping_run_uuid IS '동일 요청 내 여러 스코핑 실행을 그룹화하는 uuid입니다. 이 uuid를 `commit_generation_requests`에서 참조합니다.';
COMMENT ON COLUMN scoping_results.scoping_stage_name IS '스코핑 단계의 이름입니다 (예: 정적 분석, 임베딩 유사도).';
COMMENT ON COLUMN scoping_results.scoping_stage_order IS '스코핑 단계의 순서를 나타냅니다.';
COMMENT ON COLUMN scoping_results.target_element_instance_id IS '스코핑 대상이 된 코드 요소 인스턴스의 id입니다.';
COMMENT ON COLUMN scoping_results.base_element_instance_id IS '스코핑의 기준이 된 코드 요소 인스턴스의 id (선택적)입니다.';
COMMENT ON COLUMN scoping_results.scoping_method IS '사용된 스코핑 방법 또는 알고리즘의 이름입니다.';
COMMENT ON COLUMN scoping_results.score IS '스코핑 방법에 따른 점수 (유사도, 관련도 등)입니다.';
COMMENT ON COLUMN scoping_results.rank_within_stage IS '해당 스코핑 단계 내에서의 순위입니다.';
COMMENT ON COLUMN scoping_results.is_selected_for_next_stage IS '이 코드 요소가 다음 단계 또는 최종 컨텍스트로 선택되었는지 여부입니다.';
COMMENT ON COLUMN scoping_results.selection_reason IS '선택 또는 제외된 구체적인 이유입니다 (선택적).';
COMMENT ON COLUMN scoping_results.scoping_parameters IS '해당 스코핑 실행 시 사용된 파라미터 (임계값, Top-N 등)를 JSONB로 저장합니다.';
COMMENT ON COLUMN scoping_results.scoping_timestamp IS '이 스코핑 결과 항목이 기록된 시각입니다.';
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
    llm_request_log_uuid id, -- REFERENCES llm_request_log(uuid) ON DELETE SET NULL, (02_llm_module/02_llm_request_log.sql 참조)
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
COMMENT ON COLUMN generated_technical_descriptions.request_uuid IS '이 기술 설명서가 생성된 원본 커밋 생성 요청의 id입니다.';
COMMENT ON COLUMN generated_technical_descriptions.element_instance_id IS '이 기술 설명서가 설명하는 대상 코드 요소 인스턴스의 id입니다.';
COMMENT ON COLUMN generated_technical_descriptions.description_title IS '생성된 기술 설명서의 제목입니다 (선택적).';
COMMENT ON COLUMN generated_technical_descriptions.description_content IS 'LLM이 생성한 기술 설명서의 본문 내용입니다.';
COMMENT ON COLUMN generated_technical_descriptions.content_format IS '기술 설명서 내용의 형식입니다 (예: markdown, plaintext).';
COMMENT ON COLUMN generated_technical_descriptions.llm_model_name IS '기술 설명서 생성에 사용된 LLM의 모델명입니다.';
COMMENT ON COLUMN generated_technical_descriptions.llm_generation_parameters IS 'LLM 호출 시 사용된 주요 생성 파라미터들을 JSONB 형태로 저장합니다.';
COMMENT ON COLUMN generated_technical_descriptions.llm_request_log_uuid IS '실제 LLM API 호출에 대한 로그 uuid (llm_request_log.uuid 참조)입니다.';
COMMENT ON COLUMN generated_technical_descriptions.generation_timestamp IS '기술 설명서가 LLM에 의해 생성된 시각입니다.';
COMMENT ON COLUMN generated_technical_descriptions.version IS '기술 설명서의 버전 번호입니다 (스케일업 시 사용).';
COMMENT ON COLUMN generated_technical_descriptions.is_current_version IS '이 설명서가 해당 코드 요소에 대한 현재 유효한 최신 버전인지 여부를 나타냅니다 (스케일업 시 사용).';


-- 인덱스
CREATE INDEX uuidx_gtd_request_uuid ON generated_technical_descriptions(request_uuid);
CREATE INDEX uuidx_gtd_element_instance_id ON generated_technical_descriptions(element_instance_id);
CREATE INDEX uuidx_gtd_request_element_instance ON generated_technical_descriptions(request_uuid, element_instance_id);
CREATE INDEX uuidx_gtd_llm_model_name ON generated_technical_descriptions(llm_model_name);
-- (스케일업 시) 버전 관리를 위한 인덱스
-- CREATE INDEX uuidx_gtd_element_instance_version ON generated_technical_descriptions(element_instance_id, version DESC) WHERE is_current_version = TRUE;


-- FK 제약조건은 참조하는 테이블(llm_request_log)이 먼저 생성된 후 ALTER TABLE로 추가하는 것을 권장
-- ALTER TABLE generated_technical_descriptions ADD CONSTRAINT fk_gtd_llm_request_log FOREIGN KEY (llm_request_log_uuid) REFERENCES llm_request_log(uuid) ON DELETE SET NULL;


-- updated_at 컬럼 자동 갱신 트리거 (00_common_functions_and_types.sql 에 set_updated_at 함수 정의 가정)
CREATE TRIGGER trg_set_updated_at_generated_technical_descriptions
BEFORE UPDATE ON generated_technical_descriptions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

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
                                                                                  -- (00_repo_enums_and_types.sql 에 정의될 ENUM)
                                                                                  -- 주로 'COMMIT_MESSAGE_GENERATION'이 되겠지만, 향후 다른 LLM 호출 단계에서도 활용 가능

    context_element_type llm_input_context_type_enum NOT NULL, -- 입력 컨텍스트 요소의 타입
                                                               -- (00_repo_enums_and_types.sql 에 정의될 ENUM)
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
COMMENT ON COLUMN llm_input_context_details.request_uuid IS '이 입력 컨텍스트가 사용된 커밋 생성 요청의 id입니다.';
COMMENT ON COLUMN llm_input_context_details.llm_call_stage IS '이 컨텍스트 정보가 사용된 LLM 호출의 단계를 나타냅니다 (주로 커밋 메시지 생성 단계).';
COMMENT ON COLUMN llm_input_context_details.context_element_type IS '입력된 컨텍스트 요소의 타입을 나타냅니다 (00_repo_enums_and_types.sql에 정의된 llm_input_context_type_enum 값).';
COMMENT ON COLUMN llm_input_context_details.context_element_reference_uuid IS '해당 컨텍스트 요소의 원본 데이터가 저장된 테이블의 레코드 id입니다.';
COMMENT ON COLUMN llm_input_context_details.order_in_prompt IS '프롬프트 내에서 이 컨텍스트 요소가 포함된 상대적인 순서입니다 (선택적).';
COMMENT ON COLUMN llm_input_context_details.importance_score IS '이 컨텍스트 요소의 상대적인 중요도 또는 가중치 점수입니다 (선택적).';
COMMENT ON CONSTRAINT uq_llm_input_context_detail ON llm_input_context_details IS '동일 요청, 동일 LLM 호출 단계에서 특정 타입의 특정 참조 uuid를 가진 컨텍스트 요소는 유일해야 합니다.';


-- 인덱스
CREATE INDEX uuidx_licd_request_uuid_stage ON llm_input_context_details(request_uuid, llm_call_stage);
CREATE INDEX uuidx_licd_context_type_ref_uuid ON llm_input_context_details(context_element_type, context_element_reference_uuid);

-- updated_at 컬럼 자동 갱신 트리거 (00_common_functions_and_types.sql 에 set_updated_at 함수 정의 가정)
CREATE TRIGGER trg_set_updated_at_llm_input_context_details
BEFORE UPDATE ON llm_input_context_details
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- (00_repo_enums_and_types.sql 에 정의될 ENUM 예시)
-- CREATE TYPE llm_call_stage_enum AS ENUM (
--     'TECHNICAL_DESCRIPTION_GENERATION', -- 1차 LLM 호출
--     'COMMIT_MESSAGE_GENERATION',      -- 2차 LLM 호출
--     'CODE_REFACTORING_SUGGESTION',  -- (향후 확장)
--     'GENERAL_QUERY'                 -- (향후 확장)
-- );

-- CREATE TYPE llm_input_context_type_enum AS ENUM (
--     'SNAPSHOT_FILE_INSTANCE_CODE',    -- snapshot_file_instances (실제 파일 코드 조각)
--     'GENERATED_TECHNICAL_DESCRIPTION',-- generated_technical_descriptions (1차 LLM 생성 설명서)
--     'FILE_DIFF_FRAGMENT',             -- file_diff_fragments (Diff 정보)
--     'README_SUMMARY_CONTENT',         -- (README 요약 저장 테이블 또는 값)
--     'FILE_ANALYSIS_METRIC',           -- file_analysis_metrics (정적 분석 결과)
--     'CODE_ELEMENT_RELATION',          -- code_element_relations (코드 요소 간 관계 정보)
--     'SCOPING_RESULT_SUMMARY',         -- scoping_results (스코핑 결과 요약)
--     'USER_PROVuuidED_INSTRUCTION',      -- 사용자가 직접 입력한 지시사항
--     'COMMIT_MESSAGE_TEMPLATE',        -- 적용된 커밋 메시지 템플릿
--     'REPOSITORY_INFO',                -- repositories (리포지토리 기본 정보)
--     'SYSTEM_PROMPT_CONFIG'            -- 시스템 레벨의 공통 프롬프트 설정
-- );