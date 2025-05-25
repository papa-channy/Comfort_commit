-- =====================================================================================
-- I. Repository (저장소) 계층
-- =====================================================================================

-- ENUM 타입 정의 (필요시 테이블 생성 전 실행)
CREATE TYPE repo_vcs_platform_enum AS ENUM ('github', 'gitlab', 'bitbucket', 'other');
CREATE TYPE repo_visibility_enum AS ENUM ('public', 'private', 'internal');
CREATE TYPE repo_connection_status_enum AS ENUM ('pending', 'connected', 'disconnected', 'error', 'syncing');
CREATE TYPE repo_access_level_enum AS ENUM ('owner', 'admin', 'maintainer', 'developer', 'viewer', 'guest');

-- 1. repositories (저장소 마스터 정보)
CREATE TABLE repositories (
    repo_uuid UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_uuid UUID NOT NULL REFERENCES user_info(uuid) ON DELETE RESTRICT, -- 사용자가 소유한 리포가 있으면 탈퇴 불가 (또는 다른 정책)
    name TEXT NOT NULL,
    vcs_platform repo_vcs_platform_enum NOT NULL,
    visibility repo_visibility_enum DEFAULT 'private',
    default_branch_name TEXT DEFAULT 'main',
    repository_created_at_on_platform TIMESTAMP,
    description_text TEXT,
    primary_language_detected TEXT, -- ENUM으로 변경 가능
    archived_status BOOLEAN DEFAULT FALSE,
    service_registration_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_updated_at_metadata TIMESTAMP, -- 이 로우의 메타데이터 변경일 (트리거로 관리)
    CONSTRAINT uq_repo_owner_platform_name UNIQUE (owner_uuid, vcs_platform, name) -- 한 사용자가 동일 플랫폼에 동일 이름 리포 중복 등록 방지
);
CREATE INDEX idx_repo_owner_uuid ON repositories(owner_uuid);
CREATE TRIGGER set_updated_at_repositories
    BEFORE UPDATE ON repositories
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 2. repository_connections (저장소 연동 상태 및 서비스 설정)
CREATE TABLE repository_connections (
    repo_uuid UUID PRIMARY KEY REFERENCES repositories(repo_uuid) ON DELETE CASCADE,
    connection_status repo_connection_status_enum DEFAULT 'pending',
    last_successful_connection_at TIMESTAMP,
    last_connection_attempt_at TIMESTAMP,
    connection_error_details TEXT,
    webhook_id_on_platform TEXT,
    access_token_id_for_repo TEXT, -- 실제 토큰은 별도 보안 저장소, 여기엔 식별자나 상태만
    comfort_commit_config_json JSONB DEFAULT '{}'::JSONB, -- auto_analysis, ai_model_pref 등
    updated_at TIMESTAMP -- 트리거로 관리
);
CREATE INDEX idx_repo_conn_status ON repository_connections(connection_status);
CREATE TRIGGER set_updated_at_repository_connections
    BEFORE UPDATE ON repository_connections
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 3. repository_access_permissions (저장소 접근 권한)
CREATE TABLE repository_access_permissions (
    permission_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    repo_uuid UUID NOT NULL REFERENCES repositories(repo_uuid) ON DELETE CASCADE,
    user_uuid UUID NOT NULL REFERENCES user_info(uuid) ON DELETE CASCADE,
    access_level repo_access_level_enum NOT NULL,
    granted_by_user_uuid UUID REFERENCES user_info(uuid) ON DELETE SET NULL,
    permission_start_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    permission_end_date TIMESTAMP,
    last_updated_at TIMESTAMP, -- 트리거로 관리
    CONSTRAINT uq_repo_user_permission UNIQUE (repo_uuid, user_uuid) -- 한 유저는 한 리포에 하나의 권한만 가짐
);
CREATE INDEX idx_repo_perm_user ON repository_access_permissions(user_uuid);
CREATE INDEX idx_repo_perm_repo ON repository_access_permissions(repo_uuid);
CREATE TRIGGER set_updated_at_repository_access_permissions
    BEFORE UPDATE ON repository_access_permissions
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =====================================================================================
-- II. Code Snapshot (코드 분석 시점) 계층
-- =====================================================================================

CREATE TYPE snapshot_analysis_status_enum AS ENUM ('pending', 'queued', 'processing', 'completed', 'partial_success', 'failed', 'cancelled');
CREATE TYPE snapshot_trigger_event_enum AS ENUM ('webhook_push', 'manual_sync', 'scheduled_scan', 'initial_registration');

-- 4. code_snapshots (코드 분석 스냅샷 마스터)
CREATE TABLE code_snapshots (
    snapshot_uuid UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    repo_uuid UUID NOT NULL REFERENCES repositories(repo_uuid) ON DELETE CASCADE,
    git_commit_hash TEXT NOT NULL, -- 해당 스냅샷의 기준 커밋
    parent_commit_hashes TEXT[],   -- 복수 पैरेंट 가능성
    commit_message_original TEXT,
    committer_name TEXT,
    committer_email TEXT,
    committed_at_on_platform TIMESTAMP, -- Git 플랫폼에서의 실제 커밋 시간
    analysis_trigger_event snapshot_trigger_event_enum,
    analysis_start_time TIMESTAMP,
    analysis_end_time TIMESTAMP,
    analysis_status snapshot_analysis_status_enum DEFAULT 'pending',
    analysis_error_details TEXT,
    snapshot_created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, -- 이 레코드 생성 시간 (Comfort Commit DB 기준)
    CONSTRAINT uq_repo_commit_hash UNIQUE (repo_uuid, git_commit_hash) -- 한 리포의 특정 커밋 해시에 대한 스냅샷은 유일
);
CREATE INDEX idx_cs_repo_commit ON code_snapshots(repo_uuid, git_commit_hash);
CREATE INDEX idx_cs_status ON code_snapshots(analysis_status);
CREATE INDEX idx_cs_committed_at ON code_snapshots(committed_at_on_platform DESC);

-- 5. directory_structures (디렉토리 구조 - 스냅샷별)
CREATE TABLE directory_structures (
    directory_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    snapshot_uuid UUID NOT NULL REFERENCES code_snapshots(snapshot_uuid) ON DELETE CASCADE,
    parent_directory_id UUID REFERENCES directory_structures(directory_id) ON DELETE CASCADE, -- 최상위 디렉토리는 NULL
    directory_path_text TEXT NOT NULL, -- 전체 경로
    directory_name TEXT NOT NULL,
    nesting_level INT NOT NULL,
    tree_structure_json JSONB, -- 하위 디렉토리/파일 구조 요약 (선택적 최적화용)
    CONSTRAINT uq_snapshot_dir_path UNIQUE (snapshot_uuid, directory_path_text)
);
CREATE INDEX idx_ds_snapshot_parent ON directory_structures(snapshot_uuid, parent_directory_id);
CREATE INDEX idx_ds_path_text_gin ON directory_structures USING GIN (to_tsvector('simple', directory_path_text)); -- 경로 검색용 (GIN으로 변경)

-- =====================================================================================
-- III. File (파일) 계층
-- =====================================================================================
CREATE TYPE file_detected_language_enum AS ENUM ('python', 'javascript', 'typescript', 'java', 'go', 'csharp', 'cpp', 'ruby', 'php', 'swift', 'kotlin', 'rust', 'markdown', 'json', 'yaml', 'text', 'binary', 'unknown');

-- 6. file_identities (파일 식별자 마스터 - 파일 경로의 생명주기)
CREATE TABLE file_identities (
    file_identity_uuid UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    repo_uuid UUID NOT NULL REFERENCES repositories(repo_uuid) ON DELETE CASCADE,
    initial_file_path TEXT NOT NULL, -- 이 파일이 처음 등장했을 때의 경로
    created_at_snapshot_uuid UUID NOT NULL REFERENCES code_snapshots(snapshot_uuid), -- 처음 식별된 스냅샷
    CONSTRAINT uq_file_identity_repo_path UNIQUE (repo_uuid, initial_file_path)
);
CREATE INDEX idx_fi_repo_path ON file_identities(repo_uuid, initial_file_path);

-- 7. snapshot_file_instances (특정 스냅샷에서의 파일 "인스턴스")
CREATE TABLE snapshot_file_instances (
    snapshot_file_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    snapshot_uuid UUID NOT NULL REFERENCES code_snapshots(snapshot_uuid) ON DELETE CASCADE,
    file_identity_uuid UUID NOT NULL REFERENCES file_identities(file_identity_uuid) ON DELETE RESTRICT,
    current_file_path TEXT NOT NULL, -- 이 스냅샷에서의 파일 경로 (rename/move 고려)
    directory_id UUID REFERENCES directory_structures(directory_id) ON DELETE SET NULL,
    file_content_hash TEXT,
    file_size_bytes BIGINT,
    line_of_code_count INT,
    detected_language file_detected_language_enum DEFAULT 'unknown',
    is_binary BOOLEAN DEFAULT FALSE,
    file_mode_bits TEXT,
    symlink_target_path TEXT,
    is_deleted_in_this_snapshot BOOLEAN DEFAULT FALSE,
    change_type_from_parent_snapshot TEXT, -- ENUM: 'added', 'modified', 'deleted', 'renamed', 'type_changed'
    CONSTRAINT uq_snapshot_file_identity UNIQUE (snapshot_uuid, file_identity_uuid),
    CONSTRAINT uq_snapshot_current_path UNIQUE (snapshot_uuid, current_file_path)
);
CREATE INDEX idx_sfi_snapshot_identity ON snapshot_file_instances(snapshot_uuid, file_identity_uuid);
CREATE INDEX idx_sfi_content_hash ON snapshot_file_instances(file_content_hash) WHERE file_content_hash IS NOT NULL;
CREATE INDEX idx_sfi_language ON snapshot_file_instances(detected_language);
CREATE INDEX idx_sfi_directory_id ON snapshot_file_instances(directory_id); -- 디렉토리별 파일 조회

-- 8. file_analysis_metrics (파일 분석 메트릭 - 스냅샷별)
CREATE TABLE file_analysis_metrics (
    metric_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    snapshot_file_id UUID NOT NULL REFERENCES snapshot_file_instances(snapshot_file_id) ON DELETE CASCADE,
    metric_type TEXT NOT NULL,
    metric_value_numeric NUMERIC,
    metric_value_text TEXT,
    metric_value_json JSONB,
    analyzed_by_tool_name TEXT,
    analysis_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_file_metric_type UNIQUE (snapshot_file_id, metric_type, analyzed_by_tool_name)
);
CREATE INDEX idx_fam_snapshot_file_type ON file_analysis_metrics(snapshot_file_id, metric_type);

-- =====================================================================================
-- IV. Code Element (코드 요소) 계층
-- =====================================================================================
CREATE TYPE code_element_type_enum AS ENUM ('module', 'namespace', 'class', 'interface', 'struct', 'enum_def', 'function', 'method', 'constructor', 'destructor', 'property', 'event', 'global_variable', 'local_variable', 'parameter', 'type_alias', 'macro_definition', 'comment_block', 'annotation', 'import_statement', 'export_statement', 'unknown_element');
CREATE TYPE code_element_visibility_enum AS ENUM ('public', 'private', 'protected', 'internal', 'package_private', 'file_private');

-- 9. code_element_identities (코드 요소 식별자 마스터)
CREATE TABLE code_element_identities (
    element_identity_uuid UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    repo_uuid UUID NOT NULL REFERENCES repositories(repo_uuid) ON DELETE CASCADE,
    element_type code_element_type_enum NOT NULL,
    language_specific_type TEXT,
    fully_qualified_name TEXT NOT NULL,
    initial_snapshot_uuid UUID NOT NULL REFERENCES code_snapshots(snapshot_uuid),
    CONSTRAINT uq_element_identity_repo_fqn_type UNIQUE (repo_uuid, fully_qualified_name, element_type, language_specific_type)
);
CREATE INDEX idx_cei_repo_fqn ON code_element_identities(repo_uuid, fully_qualified_name);
CREATE INDEX idx_cei_type ON code_element_identities(element_type);

-- 10. snapshot_code_element_instances (특정 스냅샷에서의 코드 요소 "인스턴스")
CREATE TABLE snapshot_code_element_instances (
    element_instance_uuid UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    snapshot_file_id UUID NOT NULL REFERENCES snapshot_file_instances(snapshot_file_id) ON DELETE CASCADE,
    element_identity_uuid UUID NOT NULL REFERENCES code_element_identities(element_identity_uuid) ON DELETE RESTRICT,
    parent_element_instance_uuid UUID REFERENCES snapshot_code_element_instances(element_instance_uuid) ON DELETE CASCADE,
    element_name_in_file TEXT NOT NULL,
    start_line_number INT,
    end_line_number INT,
    start_column_number INT,
    end_column_number INT,
    code_block_content_hash TEXT,
    docstring_content_hash TEXT,
    cyclomatic_complexity_value INT,
    parameter_metadata_json JSONB,
    return_type_metadata_json JSONB,
    visibility_modifier code_element_visibility_enum,
    is_static BOOLEAN,
    is_abstract BOOLEAN,
    is_async BOOLEAN,
    is_deprecated BOOLEAN,
    annotations_or_decorators_json JSONB,
    change_type_from_parent_snapshot TEXT, -- ENUM: 'added', 'modified', 'deleted', 'moved'
    CONSTRAINT uq_snapshot_element_identity_pos UNIQUE (snapshot_file_id, element_identity_uuid, start_line_number, start_column_number)
);
CREATE INDEX idx_scei_snapshot_file_identity ON snapshot_code_element_instances(snapshot_file_id, element_identity_uuid);
CREATE INDEX idx_scei_content_hash ON snapshot_code_element_instances(code_block_content_hash);
CREATE INDEX idx_scei_parent_element ON snapshot_code_element_instances(parent_element_instance_uuid);

-- 11. code_element_relations (코드 요소 간 관계 - 스냅샷 귀속)
CREATE TYPE code_relation_type_enum AS ENUM ('calls_function', 'calls_method', 'instantiates_class', 'inherits_from_class', 'implements_interface', 'uses_type_annotation', 'references_global_variable', 'imports_module_symbol', 'raises_exception', 'catches_exception', 'reads_file_io', 'writes_file_io', 'uses_environment_variable', 'accesses_member', 'extended_by', 'overrides_method', 'associated_with_test');

CREATE TABLE code_element_relations (
    relation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    snapshot_uuid UUID NOT NULL REFERENCES code_snapshots(snapshot_uuid) ON DELETE CASCADE,
    source_element_instance_uuid UUID NOT NULL REFERENCES snapshot_code_element_instances(element_instance_uuid) ON DELETE CASCADE,
    target_element_instance_uuid UUID REFERENCES snapshot_code_element_instances(element_instance_uuid) ON DELETE SET NULL, -- 내부 참조, 삭제 시 관계만 NULL
    target_external_fqn TEXT,
    relation_type code_relation_type_enum NOT NULL,
    relation_details_json JSONB,
    relation_location_line INT,
    relation_location_column INT
);
CREATE INDEX idx_cer_snapshot_source ON code_element_relations(snapshot_uuid, source_element_instance_uuid);
CREATE INDEX idx_cer_snapshot_target ON code_element_relations(snapshot_uuid, target_element_instance_uuid) WHERE target_element_instance_uuid IS NOT NULL;
CREATE INDEX idx_cer_snapshot_relation_type ON code_element_relations(snapshot_uuid, relation_type);

-- 12. code_element_embeddings (코드 요소 임베딩 - 내용 해시 기준)
CREATE TABLE code_element_embeddings (
    embedding_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    element_instance_uuid UUID UNIQUE NOT NULL REFERENCES snapshot_code_element_instances(element_instance_uuid) ON DELETE CASCADE,
    embedding_model_name TEXT NOT NULL,
    embedding_vector BYTEA, -- 또는 VECTOR 타입
    vector_dimensions INT,
    embedding_created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_element_instance_model UNIQUE (element_instance_uuid, embedding_model_name) -- 이미 PK로 UNIQUE 보장, element_instance_uuid가 UNIQUE FK이므로
);
CREATE INDEX idx_cee_element_identity_model ON code_element_embeddings(element_instance_uuid, embedding_model_name); -- element_instance_uuid로 변경

-- =====================================================================================
-- V. Commit Generation & Linkage 계층
-- =====================================================================================
CREATE TYPE commit_request_initiator_enum AS ENUM ('manual_web_ui', 'ide_extension_context_menu', 'ide_extension_on_save_hook', 'scheduled_batch_analysis', 'webhook_event_driven', 'cli_command');
CREATE TYPE commit_request_status_enum AS ENUM ('pending_analysis', 'analysis_in_progress', 'analysis_completed_pending_message', 'message_generation_in_progress', 'draft_available', 'user_review_pending', 'finalized', 'committed_to_git', 'failed_analysis', 'failed_message_generation', 'cancelled_by_user', 'error_internal');
CREATE TYPE generated_message_status_enum AS ENUM ('draft_generated', 'user_editing', 'approved_by_user', 'rejected_by_user', 'committed_to_git_externally', 'superseded_by_new_draft');
CREATE TYPE commit_approval_method_enum AS ENUM ('web_ui_click', 'slack_command', 'mobile_app_tap', 'ide_extension_action', 'api_call');

-- 13. commit_generation_requests (커밋 생성 요청)
CREATE TABLE commit_generation_requests (
    request_uuid UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    repo_uuid UUID NOT NULL REFERENCES repositories(repo_uuid) ON DELETE CASCADE,
    user_uuid UUID NOT NULL REFERENCES user_info(uuid) ON DELETE CASCADE, -- 요청자
    initiating_event_type commit_request_initiator_enum NOT NULL,
    target_from_git_commit_hash TEXT,
    target_to_git_commit_hash TEXT NOT NULL,
    target_snapshot_uuid UUID REFERENCES code_snapshots(snapshot_uuid) ON DELETE SET NULL,
    selected_changed_items_json JSONB, -- 예: {"files": ["path/to/file.py"], "functions": ["uuid_of_function_instance"]}
    user_provided_intent_text TEXT,
    custom_prompt_instructions TEXT,
    requested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processing_status commit_request_status_enum DEFAULT 'pending_analysis',
    processing_error_details TEXT,
    last_updated_at TIMESTAMP
);
CREATE INDEX idx_cgr_repo_user_status ON commit_generation_requests(repo_uuid, user_uuid, processing_status);
CREATE INDEX idx_cgr_status_requested_at ON commit_generation_requests(processing_status, requested_at DESC);
CREATE TRIGGER set_updated_at_commit_generation_requests
    BEFORE UPDATE ON commit_generation_requests
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 14. generated_commit_contents (생성된 커밋 내용 - 버전 관리 포함)
CREATE TABLE generated_commit_contents (
    commit_content_uuid UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    request_uuid UUID NOT NULL REFERENCES commit_generation_requests(request_uuid) ON DELETE CASCADE,
    llm_request_log_id BIGINT REFERENCES llm_request_log(id) ON DELETE SET NULL, -- llm_request_log.id 타입이 BIGSERIAL이므로 BIGINT
    draft_version_number INT DEFAULT 1,
    generated_title_text TEXT,
    generated_body_markdown TEXT,
    generated_explanation_text TEXT,
    llm_model_used TEXT, -- 예: 'gpt-4o', 'claude-3-sonnet'
    llm_temperature_used NUMERIC(3,2),
    llm_token_counts_json JSONB, -- {"prompt": 1200, "completion": 300, "total": 1500}
    llm_processing_duration_ms INT,
    llm_cost_usd NUMERIC(10,7),
    llm_confidence_score NUMERIC(3,2),
    status generated_message_status_enum DEFAULT 'draft_generated',
    user_edit_history_json JSONB,
    created_at_draft TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_edited_at TIMESTAMP,
    CONSTRAINT uq_request_draft_version UNIQUE (request_uuid, draft_version_number)
);
CREATE INDEX idx_gcc_request_version ON generated_commit_contents(request_uuid, draft_version_number);
CREATE INDEX idx_gcc_status ON generated_commit_contents(status);
CREATE TRIGGER set_updated_at_generated_commit_contents -- last_edited_at 관리용
    BEFORE UPDATE ON generated_commit_contents
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- 15. finalized_commits (최종 확정된 커밋 정보 및 Git 연동)
CREATE TABLE finalized_commits (
    finalized_commit_uuid UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    commit_content_uuid UUID UNIQUE NOT NULL REFERENCES generated_commit_contents(commit_content_uuid) ON DELETE RESTRICT,
    approved_by_user_uuid UUID NOT NULL REFERENCES user_info(uuid) ON DELETE RESTRICT,
    approval_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    approval_method_detail commit_approval_method_enum,
    final_git_commit_hash TEXT UNIQUE,
    git_commit_timestamp_on_platform TIMESTAMP,
    pushed_to_remote_branch_name TEXT,
    comfort_commit_service_commit_time TIMESTAMP,
    notes_on_finalization TEXT,
    revert_of_commit_hash TEXT -- 만약 이 커밋이 되돌리기 커밋이라면 원본 커밋 해시
);
CREATE INDEX idx_fc_content_uuid ON finalized_commits(commit_content_uuid);
CREATE INDEX idx_fc_git_hash ON finalized_commits(final_git_commit_hash) WHERE final_git_commit_hash IS NOT NULL;
CREATE INDEX idx_fc_user_approved ON finalized_commits(approved_by_user_uuid);

-- =====================================================================================
-- VI. Supporting Tables (지원 테이블 - 기존 제안 확장)
-- =====================================================================================

-- 16. system_defined_enums (선택적, DB ENUM을 더 선호)
-- CREATE TABLE system_defined_enums ( ... );

-- 17. analysis_rule_configs (코드 분석 규칙/휴리스틱 설정)
CREATE TABLE analysis_rule_configs (
  rule_config_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  repo_uuid UUID REFERENCES repositories(repo_uuid) ON DELETE CASCADE,
  language_code file_detected_language_enum, -- file_detected_language_enum 재활용
  rule_name TEXT NOT NULL,
  rule_parameters_json JSONB,
  is_active_rule BOOLEAN DEFAULT TRUE,
  description TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP
);
CREATE INDEX idx_arc_repo_lang_name ON analysis_rule_configs(repo_uuid, language_code, rule_name);
CREATE TRIGGER set_updated_at_analysis_rule_configs
    BEFORE UPDATE ON analysis_rule_configs
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =====================================================================================
-- VII. 사용자 정의 규칙/정책 관련 테이블
-- =====================================================================================
CREATE TYPE user_rule_condition_type_enum AS ENUM ('file_path_pattern', 'change_type_is', 'min_lines_changed', 'affected_function_name_matches', 'has_keyword_in_diff');
CREATE TYPE user_rule_action_type_enum AS ENUM ('prepend_to_title', 'append_to_body', 'require_keyword_in_title', 'set_commit_type_prefix', 'add_issue_tracker_link');

-- 18. user_defined_commit_rules
CREATE TABLE user_defined_commit_rules (
    rule_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_uuid UUID NOT NULL REFERENCES user_info(uuid) ON DELETE CASCADE,
    repo_uuid UUID REFERENCES repositories(repo_uuid) ON DELETE CASCADE,
    rule_name TEXT NOT NULL,
    description TEXT,
    -- conditions_json JSONB NOT NULL, -- 개별 테이블로 분리 제안
    is_active BOOLEAN DEFAULT TRUE,
    priority INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP
);
CREATE INDEX idx_udcr_user_repo_active ON user_defined_commit_rules(user_uuid, repo_uuid, is_active, priority);
CREATE TRIGGER set_updated_at_user_defined_commit_rules
    BEFORE UPDATE ON user_defined_commit_rules
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 18a. user_defined_commit_rule_conditions (규칙 조건 상세)
CREATE TABLE user_defined_commit_rule_conditions (
    condition_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_id UUID NOT NULL REFERENCES user_defined_commit_rules(rule_id) ON DELETE CASCADE,
    condition_type user_rule_condition_type_enum NOT NULL,
    condition_parameters_json JSONB NOT NULL, -- 예: {"pattern": "*.py"}, {"change_type": "modified"}, {"min_lines": 10}
    logical_operator_with_next TEXT DEFAULT 'AND' -- ENUM: 'AND', 'OR' (다음 조건과의 관계)
);
CREATE INDEX idx_udcrc_rule_id ON user_defined_commit_rule_conditions(rule_id);

-- 18b. user_defined_commit_rule_actions (규칙 액션 상세)
CREATE TABLE user_defined_commit_rule_actions (
    action_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_id UUID NOT NULL REFERENCES user_defined_commit_rules(rule_id) ON DELETE CASCADE,
    action_type user_rule_action_type_enum NOT NULL,
    action_parameters_json JSONB NOT NULL -- 예: {"prefix": "[BUGFIX]"}, {"keyword": "critical"}, {"issue_url_template": "https://jira.example.com/browse/{issue_id}"}
);
CREATE INDEX idx_udcra_rule_id ON user_defined_commit_rule_actions(rule_id);


-- 19. analysis_ignore_patterns
CREATE TYPE ignore_pattern_type_enum AS ENUM ('file_path_glob', 'directory_path_prefix', 'code_block_signature_regex', 'content_regex_match', 'file_extension_exact');
CREATE TABLE analysis_ignore_patterns (
    pattern_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_uuid UUID NOT NULL REFERENCES user_info(uuid) ON DELETE CASCADE,
    repo_uuid UUID REFERENCES repositories(repo_uuid) ON DELETE CASCADE,
    pattern_type ignore_pattern_type_enum NOT NULL,
    pattern_value TEXT NOT NULL,
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    scope TEXT DEFAULT 'global', -- ENUM: 'global_user', 'repo_specific'
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP
);
CREATE INDEX idx_aip_user_repo_scope ON analysis_ignore_patterns(user_uuid, repo_uuid, scope, is_active);
CREATE INDEX idx_aip_type_active ON analysis_ignore_patterns(pattern_type, is_active);
CREATE TRIGGER set_updated_at_analysis_ignore_patterns
    BEFORE UPDATE ON analysis_ignore_patterns
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =====================================================================================
-- VIII. 팀/조직 기능 강화 관련 테이블
-- =====================================================================================
CREATE TYPE team_member_role_enum AS ENUM ('member', 'maintainer', 'admin', 'owner_surrogate');

-- 20. organizations
CREATE TABLE organizations (
    org_uuid UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_handle TEXT NOT NULL UNIQUE, -- 조직의 고유 핸들 (예: "acme-corp")
    org_display_name TEXT NOT NULL,
    owner_user_uuid UUID NOT NULL REFERENCES user_info(uuid) ON DELETE RESTRICT,
    billing_contact_user_uuid UUID REFERENCES user_info(uuid) ON DELETE SET NULL,
    website_url TEXT,
    logo_url TEXT,
    is_verified_org BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP
);
CREATE INDEX idx_org_owner ON organizations(owner_user_uuid);
CREATE TRIGGER set_updated_at_organizations
    BEFORE UPDATE ON organizations
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 21. teams
CREATE TABLE teams (
    team_uuid UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_uuid UUID NOT NULL REFERENCES organizations(org_uuid) ON DELETE CASCADE,
    team_handle TEXT NOT NULL, -- 팀의 고유 핸들 (조직 내에서 유니크)
    team_display_name TEXT NOT NULL,
    description TEXT,
    parent_team_uuid UUID REFERENCES teams(team_uuid) ON DELETE SET NULL,
    created_by_user_uuid UUID REFERENCES user_info(uuid) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP,
    CONSTRAINT uq_org_team_handle UNIQUE (org_uuid, team_handle)
);
CREATE INDEX idx_team_org_parent ON teams(org_uuid, parent_team_uuid);
CREATE TRIGGER set_updated_at_teams
    BEFORE UPDATE ON teams
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 22. team_memberships
CREATE TABLE team_memberships (
    membership_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    team_uuid UUID NOT NULL REFERENCES teams(team_uuid) ON DELETE CASCADE,
    user_uuid UUID NOT NULL REFERENCES user_info(uuid) ON DELETE CASCADE,
    role_in_team team_member_role_enum DEFAULT 'member',
    joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP,
    CONSTRAINT uq_team_user_membership UNIQUE (team_uuid, user_uuid)
);
CREATE INDEX idx_tm_user ON team_memberships(user_uuid);
CREATE INDEX idx_tm_team_role ON team_memberships(team_uuid, role_in_team);
CREATE TRIGGER set_updated_at_team_memberships
    BEFORE UPDATE ON team_memberships
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 23. team_repository_access (팀 단위 저장소 접근 권한)
CREATE TABLE team_repository_access (
    team_access_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    team_uuid UUID NOT NULL REFERENCES teams(team_uuid) ON DELETE CASCADE,
    repo_uuid UUID NOT NULL REFERENCES repositories(repo_uuid) ON DELETE CASCADE,
    access_level repo_access_level_enum NOT NULL,
    granted_by_user_uuid UUID REFERENCES user_info(uuid) ON DELETE SET NULL,
    granted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP,
    CONSTRAINT uq_team_repo_access UNIQUE (team_uuid, repo_uuid)
);
CREATE INDEX idx_tra_repo ON team_repository_access(repo_uuid);
CREATE INDEX idx_tra_team_access_level ON team_repository_access(team_uuid, access_level);
CREATE TRIGGER set_updated_at_team_repository_access
    BEFORE UPDATE ON team_repository_access
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =====================================================================================
-- IX. 빌드/배포/이슈 트래커 연동 정보 테이블
-- =====================================================================================
CREATE TYPE external_link_source_entity_enum AS ENUM ('commit_generation_request', 'finalized_commit', 'code_snapshot', 'repository', 'user_defined_commit_rule');
CREATE TYPE external_link_system_enum AS ENUM ('jira', 'github_issues', 'gitlab_issues', 'trello', 'jenkins', 'circle_ci', 'github_actions', 'sentry', 'custom_webhook');

-- 24. external_entity_links
CREATE TABLE external_entity_links (
    link_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_entity_type external_link_source_entity_enum NOT NULL,
    source_entity_uuid UUID NOT NULL,
    external_system_type external_link_system_enum NOT NULL,
    external_entity_id TEXT NOT NULL, -- 예: "PROJ-1234"
    external_entity_url TEXT,
    relation_description TEXT, -- 예: "resolves_issue", "triggered_build", "mentioned_in"
    linked_by_user_uuid UUID REFERENCES user_info(uuid) ON DELETE SET NULL,
    linked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    metadata_json JSONB,
    is_active_link BOOLEAN DEFAULT TRUE,
    last_verified_at TIMESTAMP -- 링크 유효성 마지막 확인 시각
);
CREATE INDEX idx_eel_source_entity ON external_entity_links(source_entity_type, source_entity_uuid);
CREATE INDEX idx_eel_external_entity ON external_entity_links(external_system_type, external_entity_id);
CREATE INDEX idx_eel_active_verified ON external_entity_links(is_active_link, last_verified_at);

-- =====================================================================================
-- X. 사용자 활동 및 서비스 사용 통계 관련 상세 테이블
-- =====================================================================================
CREATE TYPE feature_usage_result_status_enum AS ENUM ('success', 'failure_user_error', 'failure_system_error', 'cancelled_by_user', 'timeout_system', 'pending_completion');

-- 25. feature_usage_logs (세분화된 기능 사용 로그)
CREATE TABLE feature_usage_logs (
    usage_log_id BIGSERIAL, -- PK는 (usage_log_id, log_timestamp)
    user_uuid UUID REFERENCES user_info(uuid) ON DELETE SET NULL,
    repo_uuid UUID REFERENCES repositories(repo_uuid) ON DELETE SET NULL,
    feature_name TEXT NOT NULL,
    sub_feature_details TEXT,
    session_id UUID REFERENCES user_session(session_id) ON DELETE SET NULL,
    usage_start_time TIMESTAMP,
    usage_duration_ms INT,
    usage_unit_count INT DEFAULT 1, -- 예: 분석된 파일 수, 생성된 메시지 수
    parameters_used_json JSONB,
    result_status feature_usage_result_status_enum,
    error_details_if_failed TEXT,
    client_platform_info_json JSONB, -- {"os": "windows", "browser": "chrome", "app_version": "1.2.3"}
    log_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (usage_log_id, log_timestamp)
) PARTITION BY RANGE (log_timestamp);
CREATE INDEX idx_ful_user_feature_time ON feature_usage_logs(user_uuid, feature_name, log_timestamp DESC);
CREATE INDEX idx_ful_repo_feature_time ON feature_usage_logs(repo_uuid, feature_name, log_timestamp DESC);
CREATE INDEX idx_ful_status_time ON feature_usage_logs(result_status, log_timestamp DESC);

-- =====================================================================================
-- XI. A/B 테스트 관리 테이블
-- =====================================================================================
CREATE TYPE ab_test_status_enum AS ENUM ('draft', 'running', 'paused', 'completed', 'archived', 'error_config');

-- 26. ab_tests_master
CREATE TABLE ab_tests_master (
    test_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    test_name TEXT NOT NULL UNIQUE,
    description TEXT,
    hypothesis TEXT,
    status ab_test_status_enum DEFAULT 'draft',
    start_date TIMESTAMP,
    end_date TIMESTAMP,
    target_audience_segment_id UUID, -- 별도 segment 테이블 참조 또는 JSONB
    -- target_audience_criteria_json JSONB,
    control_group_percentage INT DEFAULT 50 CHECK (control_group_percentage >=0 AND control_group_percentage <= 100),
    primary_metric_name TEXT, -- 예: 'commit_approval_rate'
    secondary_metrics_json JSONB, -- 예: ["avg_commit_generation_time_ms", "user_churn_rate_within_test"]
    created_by_user_uuid UUID REFERENCES user_info(uuid) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP
);
CREATE INDEX idx_abtm_name_status ON ab_tests_master(test_name, status);
CREATE TRIGGER set_updated_at_ab_tests_master
    BEFORE UPDATE ON ab_tests_master
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 27. ab_test_variants
CREATE TABLE ab_test_variants (
    variant_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    test_id UUID NOT NULL REFERENCES ab_tests_master(test_id) ON DELETE CASCADE,
    variant_name TEXT NOT NULL,
    description TEXT,
    allocation_percentage INT NOT NULL CHECK (allocation_percentage >= 0 AND allocation_percentage <= 100), -- 모든 variant 합이 100이 되도록 앱에서 관리
    configuration_overrides_json JSONB,
    is_control_group BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP,
    CONSTRAINT uq_abtv_test_name UNIQUE (test_id, variant_name)
);
CREATE INDEX idx_abtv_test_id ON ab_test_variants(test_id);
CREATE TRIGGER set_updated_at_ab_test_variants
    BEFORE UPDATE ON ab_test_variants
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 28. ab_test_user_assignments
CREATE TABLE ab_test_user_assignments (
    assignment_id BIGSERIAL PRIMARY KEY,
    test_id UUID NOT NULL REFERENCES ab_tests_master(test_id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES ab_test_variants(variant_id) ON DELETE RESTRICT, -- 변형 삭제 시 할당 기록은 남김 (또는 CASCADE)
    user_uuid UUID NOT NULL REFERENCES user_info(uuid) ON DELETE CASCADE,
    assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    -- 만약 사용자가 여러 테스트에 동시에 참여 가능, 한 테스트에는 하나의 변형만 할당된다면
    CONSTRAINT uq_abtu_test_user UNIQUE (test_id, user_uuid)
);
CREATE INDEX idx_abtu_user_test_variant ON ab_test_user_assignments(user_uuid, test_id, variant_id);

-- 29. ab_test_event_metrics (A/B 테스트 결과 이벤트 로깅 - 집계 전 원시 데이터)
CREATE TABLE ab_test_event_metrics (
    event_id BIGSERIAL, -- PK는 (event_id, event_timestamp)
    test_id UUID NOT NULL REFERENCES ab_tests_master(test_id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES ab_test_variants(variant_id) ON DELETE RESTRICT,
    user_uuid UUID NOT NULL REFERENCES user_info(uuid) ON DELETE SET NULL, -- 사용자 탈퇴 시에도 이벤트는 익명으로 남김
    metric_name TEXT NOT NULL, -- 추적 대상 메트릭 (ab_tests_master.primary_metric_name 등과 일치)
    metric_value_numeric NUMERIC,
    metric_value_text TEXT,
    event_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP, -- 파티션 키
    related_session_id UUID,
    metadata_json JSONB,
    PRIMARY KEY (event_id, event_timestamp)
) PARTITION BY RANGE (event_timestamp);
CREATE INDEX idx_abtem_test_variant_metric_time ON ab_test_event_metrics(test_id, variant_id, metric_name, event_timestamp DESC);
CREATE INDEX idx_abtem_user_metric_time ON ab_test_event_metrics(user_uuid, metric_name, event_timestamp DESC);

-- =====================================================================================
-- XII. 사용자 알림 상세 로그
-- =====================================================================================
CREATE TYPE notification_delivery_status_enum AS ENUM ('pending_dispatch', 'dispatched_to_provider', 'delivered_to_recipient', 'failed_permanently', 'failed_temporarily_will_retry', 'opened_by_recipient', 'clicked_by_recipient', 'error_invalid_address', 'user_opted_out_channel', 'unknown_status');
CREATE TYPE notification_channel_enum AS ENUM ('email_gmail', 'slack_webhook', 'kakao_bizmessage', 'discord_webhook', 'telegram_bot', 'app_push_fcm', 'app_push_apns', 'in_app_web_notification');

-- 30. notification_delivery_logs (개별 알림 발송/결과 상세 로그)
CREATE TABLE notification_delivery_logs (
    log_id BIGSERIAL, -- PK는 (log_id, log_timestamp)
    user_uuid UUID REFERENCES user_info(uuid) ON DELETE SET NULL,
    notification_template_id TEXT, -- 어떤 알림 템플릿을 사용했는지 (별도 템플릿 마스터 테이블 필요 시)
    notification_type TEXT NOT NULL, -- 예: 'commit_ready_for_review', 'new_feature_announcement'
    channel notification_channel_enum NOT NULL,
    recipient_identifier TEXT NOT NULL, -- 암호화되거나 마스킹된 주소/ID/토큰
    subject_or_title_text TEXT,
    -- content_summary_text TEXT, -- 실제 내용은 외부 저장 또는 PII 마스킹 후 저장
    -- content_reference_id TEXT, -- 외부 저장된 컨텐츠 ID
    status notification_delivery_status_enum DEFAULT 'pending_dispatch',
    dispatch_attempt_count INT DEFAULT 0,
    last_dispatch_attempt_at TIMESTAMP,
    provider_message_id TEXT, -- 외부 알림 서비스 제공자로부터 받은 메시지 ID
    provider_response_code TEXT,
    failure_reason_category TEXT, -- 예: 'invalid_address', 'network_error', 'provider_throttling'
    failure_details_text TEXT,
    opened_at TIMESTAMP,
    clicked_at TIMESTAMP,
    related_entity_type external_link_source_entity_enum, -- 알림의 대상이 된 엔티티 타입 (external_link_source_entity_enum 재활용)
    related_entity_uuid UUID,
    log_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (log_id, log_timestamp)
) PARTITION BY RANGE (log_timestamp);
CREATE INDEX idx_ndl_user_channel_status_time ON notification_delivery_logs(user_uuid, channel, status, log_timestamp DESC);
CREATE INDEX idx_ndl_type_status_time ON notification_delivery_logs(notification_type, status, log_timestamp DESC);
CREATE INDEX idx_ndl_provider_message_id ON notification_delivery_logs(provider_message_id) WHERE provider_message_id IS NOT NULL;