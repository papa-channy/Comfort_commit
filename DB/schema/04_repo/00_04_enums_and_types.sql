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
-- 0. `01_repo_main` 관련 ENUM 타입
-- =====================================================================================

-- `01_repo.sql` (repo_main 테이블) 에서 사용
CREATE TYPE repo_vcs_platform_enum AS ENUM (
    'github', 
    'gitlab', 
    'bitbucket', 
    'azure_devops', -- 추가 고려
    'aws_codecommit', -- 추가 고려
    'gitea',        -- 추가 고려
    'other'
);
COMMENT ON TYPE repo_vcs_platform_enum IS '저장소가 호스팅되는 Version Control System 플랫폼 유형입니다.';

CREATE TYPE repo_visibility_enum AS ENUM (
    'public', 
    'private', 
    'internal'
);
COMMENT ON TYPE repo_visibility_enum IS '저장소의 공개 범위입니다.';

-- `02_repo_connections.sql` (repo_connections 테이블) 에서 사용
CREATE TYPE repo_connection_status_enum AS ENUM (
    'pending_verification', 
    'connected', 
    'disconnected_by_user', 
    'error_authentication', 
    'error_permissions', 
    'error_not_found', 
    'syncing_in_progress', -- 'syncing'에서 명확화
    'temporarily_unavailable',
    'needs_re_authentication' -- 추가
);
COMMENT ON TYPE repo_connection_status_enum IS '저장소와 Comfort Commit 서비스 간의 연동 상태입니다.';

CREATE TYPE repo_connection_method_enum AS ENUM (
    'oauth_app', 
    'personal_access_token', 
    'ssh_key_reference',
    'github_app_installation', -- 추가
    'gitlab_integration',      -- 추가
    'bitbucket_app_password',  -- 추가
    'github_codespaces', 
    'other_connection_method' -- 'other'에서 명확화
);
COMMENT ON TYPE repo_connection_method_enum IS '저장소에 접근하기 위해 우선적으로 사용되는 연결 방식입니다.';

-- `03_repo_access_permissions.sql` (repo_access_permissions 테이블) 에서 사용
CREATE TYPE repo_access_level_enum AS ENUM (
    'owner', 
    'admin', 
    'maintainer', 
    'developer', 
    'reporter', -- 'viewer' 대신 좀 더 구체적인 역할
    'viewer',   -- 유지 또는 'reporter'와 통합 고려
    'guest', 
    'no_access_explicit' -- 'no_access'에서 명확화
);
COMMENT ON TYPE repo_access_level_enum IS 'Comfort Commit 서비스 내에서 사용자의 특정 저장소에 대한 접근 수준을 정의합니다.';


-- =====================================================================================
-- 1. `02_code_snapshots` 관련 ENUM 및 타입
-- =====================================================================================

-- `01_code_snapshots.sql` (code_snapshots 테이블) 에서 사용
CREATE TYPE snapshot_analysis_status_enum AS ENUM (
    'pending', 
    'queued', 
    'processing_metadata',          -- 'processing' 세분화
    'processing_diff',              -- 'processing' 세분화
    'processing_code_elements',     -- 'processing' 세분화
    'processing_embeddings',        -- 'processing' 세분화
    'completed_successfully',       -- 'completed' 명확화
    'completed_with_partial_data',  -- 'partial_success' 명확화
    'failed_during_analysis',       -- 'failed' 명확화
    'cancelled_by_user', 
    'error_internal_system'         -- 'error_internal' 명확화
);
COMMENT ON TYPE snapshot_analysis_status_enum IS '코드 스냅샷에 대한 Comfort Commit 내부 분석 작업의 진행 상태입니다.';

CREATE TYPE snapshot_trigger_event_enum AS ENUM (
    'webhook_push_event',           -- 'webhook_push' 명확화
    'manual_sync_request',          -- 'manual_sync_repo' 명확화
    'scheduled_repository_scan',    -- 'scheduled_repo_scan' 명확화
    'initial_repository_registration', -- 'initial_repo_registration' 명확화
    'commit_generation_request_dependency', -- 'commit_generation_request_target' 명확화
    'system_recovery_scan'          -- 추가
);
COMMENT ON TYPE snapshot_trigger_event_enum IS '이 코드 스냅샷 분석을 트리거한 이벤트의 유형입니다.';

-- `03_file_diff_fragments.sql` (file_diff_fragments 테이블) 에서 사용
CREATE TYPE diff_change_type_enum AS ENUM (
    'ADDED',
    'MODIFIED',
    'DELETED',
    'RENAMED',
    'COPIED',
    'TYPE_CHANGED'
);
COMMENT ON TYPE diff_change_type_enum IS '파일 또는 코드 조각의 변경 유형을 나타내는 ENUM 타입입니다.';


-- =====================================================================================
-- 2. `03_files` 관련 ENUM 및 타입
-- =====================================================================================

-- `02_snapshot_file_instances.sql` (snapshot_file_instances 테이블) 에서 사용
CREATE TYPE file_detected_language_enum AS ENUM (
    'python', 'javascript', 'typescript', 'java', 'go', 'csharp', 'cpp', 'ruby', 'php', 'swift', 'kotlin', 'rust', 'html', 'css', 'scss', 'sql', 
    'shell', 'powershell', 'dockerfile', 'terraform', 'yaml', 'json', 'xml', 'markdown', 'text', 
    'binary', 'unknown_language', 'unsupported_language'
);
COMMENT ON TYPE file_detected_language_enum IS '파일 내용 분석을 통해 감지된 프로그래밍 또는 마크업 언어의 유형입니다.';

CREATE TYPE file_change_type_enum AS ENUM (
    'added', 
    'modified', 
    'deleted', 
    'renamed', 
    'copied', 
    'type_changed',
    'unmodified',
    'unknown_change'
);
COMMENT ON TYPE file_change_type_enum IS '이전 스냅샷(또는 부모 커밋) 대비 해당 파일 인스턴스의 변경 유형입니다.';

-- `03_file_analysis_metrics.sql` (file_analysis_metrics 테이블) 에서 사용
CREATE TYPE metric_type_enum AS ENUM (
    'LINES_OF_CODE_TOTAL',
    'LINES_OF_CODE_CODE',
    'LINES_OF_CODE_COMMENT',
    'COMMENT_RATIO',
    'FILE_SIZE_BYTES',
    'LANGUAGE_uuidENTIFIED',
    'RECENT_CHANGE_INTENSITY_SCORE',
    'FILE_AGE_DAYS',
    'LAST_COMMIT_TIMESTAMP_OF_FILE',
    'LAST_MODIFIED_BY_AUTHOR',
    'NUMBER_OF_AUTHORS',
    'OWNERSHIP_PERCENTAGE_TOP_DEV',
    'DEPENDENCY_COUNT_INTERNAL',
    'DEPENDENCY_COUNT_EXTERNAL',
    'IMPORTED_MODULE_LIST_JSON',
    'EXPORTED_ELEMENT_COUNT',
    'FUNCTION_COUNT_IN_FILE',
    'CLASS_COUNT_IN_FILE',
    'COMPLEXITY_CYCLOMATIC_AVG',
    'COMPLEXITY_HALSTEAD_VOLUME',
    'LLM_CONTEXT_RELEVANCE_SCORE',
    'NEEDS_TECH_DESCRIPTION_FLAG',
    'POTENTIAL_REFACTORING_CANDuuidATE_SCORE',
    'OTHER_CUSTOM_METRIC'
);
COMMENT ON TYPE metric_type_enum IS '파일 메타정보 또는 분석된 메트릭의 종류를 나타내는 ENUM 타입입니다.';


-- =====================================================================================
-- 3. `04_code_elements` 관련 ENUM 및 타입
-- =====================================================================================

-- `01_code_element_uuidentities.sql` 및 `02_snapshot_code_element_instances.sql` 에서 사용
CREATE TYPE code_element_type_enum AS ENUM (
    'MODULE',
    'NAMESPACE',
    'CLASS',
    'INTERFACE',
    'TRAIT',
    'ENUM_TYPE',
    'ENUM_MEMBER',
    'FUNCTION',
    'METHOD',
    'CONSTRUCTOR',
    'DESTRUCTOR',
    'GETTER',
    'SETTER',
    'PROPERTY',
    'CONSTANT',
    'GLOBAL_VARIABLE',
    'LOCAL_VARIABLE',
    'TYPE_ALIAS',
    'STRUCT',
    'UNION',
    'ANNOTATION_OR_DECORATOR',
    'PARAMETER',
    'RETURN_TYPE',
    'IMPORT_STATEMENT',
    'EXPORT_STATEMENT',
    'CODE_BLOCK',
    'COMMENT_BLOCK',
    'UNKNOWN_ELEMENT'
);
COMMENT ON TYPE code_element_type_enum IS '코드 요소의 타입을 나타내는 ENUM 타입입니다 (함수, 클래스, 모듈 등).';

-- `03_code_element_relations.sql` 에서 사용
CREATE TYPE element_relation_type_enum AS ENUM (
    'CALLS_FUNCTION',
    'CALLS_METHOD',
    'CREATES_INSTANCE_OF',
    'REFERENCES_FUNCTION_POINTER',
    'THROWS_EXCEPTION',
    'CATCHES_EXCEPTION',
    'HAS_CONTROL_FLOW_TO',
    'USES_VARIABLE',
    'MODIFIES_VARIABLE',
    'DEFINES_VARIABLE_OR_PROPERTY',
    'ACCESSES_FIELD_OR_PROPERTY',
    'RETURNS_VALUE_OF_TYPE',
    'IMPORTS_MODULE_OR_FILE',
    'EXPORTS_ELEMENT',
    'INHERITS_FROM_CLASS',
    'IMPLEMENTS_INTERFACE',
    'EXTENDS_CLASS_OR_INTERFACE',
    'REFERENCES_TYPE',
    'IS_INSTANCE_OF_CLASS',
    'HAS_PARAMETER_OF_TYPE',
    'USES_GENERIC_TYPE',
    'ANNOTATED_BY_OR_DECORATED_BY',
    'ANNOTATES_OR_DECORATES',
    'DEPENDS_ON_FILE',
    'INCLUDES_HEADER',
    'RELATED_TO_SEMANTICALLY',
    'PART_OF_FEATURE',
    'ADDRESSES_REQUIREMENT',
    'CUSTOM_USER_DEFINED_RELATION'
);
COMMENT ON TYPE element_relation_type_enum IS '코드 요소들 간의 관계 유형을 나타내는 ENUM 타입입니다.';


-- =====================================================================================
-- 4. `05_commit_generation` 관련 ENUM 및 타입
-- =====================================================================================

-- `01_commit_generation_requests.sql` 에서 사용
CREATE TYPE request_status_enum AS ENUM (
    'PENDING',
    'PREPROCESSING_FILES',
    'SCOPING_INITIAL_CANDuuidATES',
    'SCOPING_STATIC_ANALYSIS',
    'SCOPING_EMBEDDING_ANALYSIS',
    'SCOPING_COMPLETED',
    'GENERATING_TECH_DESCRIPTION',
    'TECH_DESCRIPTION_READY',
    'GENERATING_COMMIT_MESSAGE',
    'COMMIT_MESSAGE_READY',
    'AWAITING_USER_REVIEW',
    'USER_APPROVED_AS_IS',
    'USER_EDITED_AND_APPROVED',
    'AUTO_COMMITTED_BY_RULE',
    'COMPLETED_SUCCESSFULLY',
    'FAILED_PREPROCESSING',
    'FAILED_SCOPING',
    'FAILED_LLM_TECH_DESCRIPTION',
    'FAILED_LLM_COMMIT_MESSAGE',
    'FAILED_GIT_COMMIT_ACTION',
    'FAILED_GIT_PUSH_ACTION',
    'CANCELLED_BY_USER',
    'TIMED_OUT_PROCESSING',
    'UNKNOWN_ERROR'
);
COMMENT ON TYPE request_status_enum IS '커밋 생성 요청의 처리 상태를 나타내는 ENUM 타입입니다.';

-- `03_finalized_commits.sql` 에서 사용
CREATE TYPE push_status_enum AS ENUM (
    'NOT_APPLICABLE',
    'NOT_PUSHED',
    'PUSH_PENDING',
    'PUSH_IN_PROGRESS',
    'PUSH_SUCCESSFUL',
    'PUSH_FAILED',
    'PUSH_PARTIAL'
);
COMMENT ON TYPE push_status_enum IS 'Git Push 작업의 상태를 나타내는 ENUM 타입입니다.';

-- `06_llm_input_context_details.sql` 에서 사용
CREATE TYPE llm_call_stage_enum AS ENUM (
    'TECHNICAL_DESCRIPTION_GENERATION',
    'COMMIT_MESSAGE_GENERATION',
    'CODE_ANALYSIS_SUMMARY',
    'CODE_REFACTORING_SUGGESTION',
    'GENERAL_QA_ABOUT_CODE',
    'OTHER_LLM_TASK'
);
COMMENT ON TYPE llm_call_stage_enum IS 'LLM 호출이 사용된 주요 단계를 나타내는 ENUM 타입입니다.';

CREATE TYPE llm_input_context_type_enum AS ENUM (
    'SNAPSHOT_FILE_INSTANCE_FULL_CODE',
    'SNAPSHOT_CODE_ELEMENT_INSTANCE_SNIPPET',
    'GENERATED_TECHNICAL_DESCRIPTION',
    'FILE_DIFF_FRAGMENT_TEXT',
    'FILE_ANALYSIS_METRIC_VALUE',
    'CODE_ELEMENT_RELATION_INFO',
    'EMBEDDING_SIMILARITY_SCORE',
    'REPOSITORY_METADATA',
    'PROJECT_README_SUMMARY',
    'DIRECTORY_STRUCTURE_OVERVIEW',
    'SCOPING_STRATEGY_APPLIED',
    'USER_DEFINED_COMMIT_RULE_TEXT',
    'COMMIT_MESSAGE_TEMPLATE_TEXT',
    'USER_DIRECT_INSTRUCTION',
    'USER_FEEDBACK_ON_PREVIOUS_OUTPUT',
    'SYSTEM_LEVEL_PROMPT_CONFIGURATION',
    'CURRENT_DATE_TIME_INFO',
    'TARGET_COMMIT_BRANCH_NAME',
    'OTHER_CONTEXT_ELEMENT'
);
COMMENT ON TYPE llm_input_context_type_enum IS 'LLM 호출 시 입력으로 사용된 컨텍스트 요소의 타입을 나타내는 ENUM 타입입니다.';


SELECT 'ENUM types for 04_repo_module created successfully.' AS status;