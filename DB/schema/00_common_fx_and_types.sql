-- =====================================================================================
-- File: 00_common_functions_and_types.sql
-- Description: Defines common PostgreSQL functions and ENUM types used across the schema.
-- Execution Order: This script should be run first before any table creation scripts.
-- =====================================================================================
--우리 근데 성능을 높일 수 있는 방법을 하나 찾았어 우리 uuid를 primary key로 id는 unique로 걸어서 순서만 바꾸면 우리가 원하는 저장공간 축소와 편리성을 동시에 얻을 수 있지 않을까?
-- -------------------------------------------------------------------------------------
-- I. Common Functions
-- -------------------------------------------------------------------------------------

-- Function to automatically set the 'updated_at' timestamp on row update

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to delete expired user sessions (to be called алкоголик by a scheduler)
CREATE OR REPLACE FUNCTION delete_expired_sessions()
RETURNS VOID AS $$
BEGIN
  DELETE FROM user_session WHERE expires_at < NOW();
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION delete_expired_sessions IS 'Deletes user sessions that have passed their expiration time. Intended for periodic execution by a scheduler (e.g., pg_cron).';

-- Function to update the status of expired rewards (to be called by a scheduler)
CREATE OR REPLACE FUNCTION expire_rewards()
RETURNS VOID AS $$
BEGIN
  UPDATE user_reward_log
  SET reward_status = 'expired'::reward_status_enum -- Ensure ENUM type is cast correctly
  WHERE reward_status = 'active'::reward_status_enum
    AND reward_expire_at IS NOT NULL
    AND reward_expire_at < NOW();
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION expire_rewards IS 'Updates the status of rewards to ''expired'' if their expiration date has passed. Intended for periodic execution by a scheduler.';

-- Function to insert a record into user_plan_history when user_plan.plan_key is updated
-- (This function's content will depend on the final structure of user_plan_history)
CREATE OR REPLACE FUNCTION insert_user_plan_history()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO user_plan_history (
    uuid,
    old_plan_key,
    new_plan_key,
    old_plan_label,
    new_plan_label,
    old_price_usd,
    new_price_usd,
    was_trial,
    changed_by,
    source,
    effective_from, -- Or OLD.updated_at / NEW.started_at
    effective_until, -- Or NEW.expires_at
    note
    -- commit_usage_snapshot, describe_usage_snapshot, etc. might need to be fetched or passed
  )
  VALUES (
    OLD.uuid,
    OLD.plan_key::TEXT,         -- Cast ENUM to TEXT for history table if it uses TEXT
    NEW.plan_key::TEXT,         -- Cast ENUM to TEXT
    OLD.plan_label,
    NEW.plan_label,
    OLD.monthly_price_usd,
    NEW.monthly_price_usd,
    OLD.is_trial_active,
    COALESCE(NEW.changed_by_actor, 'trigger'), -- Requires a way to pass actor or defaults to 'trigger'
    'plan_key_update',          -- Source of change
    OLD.updated_at,             -- Approximate old plan end
    NEW.started_at,             -- Approximate new plan start
    'Plan key changed from ' || OLD.plan_key::TEXT || ' to ' || NEW.plan_key::TEXT
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION insert_user_plan_history IS 'Automatically logs changes to user_plan.plan_key into the user_plan_history table.';


-- -------------------------------------------------------------------------------------
-- II. Common ENUM Types (Alphabetical Order by Type Name)
-- -------------------------------------------------------------------------------------

CREATE TYPE ab_test_status_enum AS ENUM (
    'draft',
    'running',
    'paused',
    'completed',
    'archived',
    'error_config'
);

CREATE TYPE code_element_type_enum AS ENUM (
    'module', 'namespace', 'class', 'interface', 'struct', 'enum_def',
    'function', 'method', 'constructor', 'destructor', 'property', 'event',
    'global_variable', 'local_variable', 'parameter', 'type_alias',
    'macro_definition', 'comment_block', 'annotation',
    'import_statement', 'export_statement', 'unknown_element'
);

CREATE TYPE code_element_visibility_enum AS ENUM (
    'public', 'private', 'protected', 'internal', 'package_private', 'file_private'
);

CREATE TYPE code_relation_type_enum AS ENUM (
    'calls_function', 'calls_method', 'instantiates_class', 'inherits_from_class',
    'implements_interface', 'uses_type_annotation', 'references_global_variable',
    'imports_module_symbol', 'raises_exception', 'catches_exception',
    'reads_file_io', 'writes_file_io', 'uses_environment_variable',
    'accesses_member', 'extended_by', 'overrides_method', 'associated_with_test'
);

CREATE TYPE commit_approval_method_enum AS ENUM (
    'web_ui_click', 'slack_command', 'mobile_app_tap', 'ide_extension_action', 'api_call'
);

CREATE TYPE commit_request_initiator_enum AS ENUM (
    'manual_web_ui', 'ide_extension_context_menu', 'ide_extension_on_save_hook',
    'scheduled_batch_analysis', 'webhook_event_driven', 'cli_command'
);

CREATE TYPE commit_request_status_enum AS ENUM (
    'pending_analysis', 'analysis_in_progress', 'analysis_completed_pending_message',
    'message_generation_in_progress', 'draft_available', 'user_review_pending',
    'finalized', 'committed_to_git', 'failed_analysis', 'failed_message_generation',
    'cancelled_by_user', 'error_internal'
);

CREATE TYPE deletion_request_status_enum AS ENUM (
    'pending', 'processing', 'completed', 'rejected', 'error'
);

CREATE TYPE external_link_source_entity_enum AS ENUM (
    'commit_generation_request', 'finalized_commit', 'code_snapshot',
    'repository', 'user_defined_commit_rule'
);

CREATE TYPE external_link_system_enum AS ENUM (
    'jira', 'github_issues', 'gitlab_issues', 'trello', 'jenkins',
    'circle_ci', 'github_actions', 'sentry', 'custom_webhook'
);

CREATE TYPE feature_usage_result_status_enum AS ENUM (
    'success', 'failure_user_error', 'failure_system_error',
    'cancelled_by_user', 'timeout_system', 'pending_completion'
);

CREATE TYPE file_detected_language_enum AS ENUM (
    'python', 'javascript', 'typescript', 'java', 'go', 'csharp', 'cpp',
    'ruby', 'php', 'swift', 'kotlin', 'rust', 'markdown', 'json', 'yaml',
    'text', 'binary', 'unknown'
);

CREATE TYPE generated_message_status_enum AS ENUM (
    'draft_generated', 'user_editing', 'approved_by_user',
    'rejected_by_user', 'committed_to_git_externally', 'superseded_by_new_draft'
);

CREATE TYPE ignore_pattern_type_enum AS ENUM (
    'file_path_glob', 'directory_path_prefix', 'code_block_signature_regex',
    'content_regex_match', 'file_extension_exact'
);

CREATE TYPE notification_channel_enum AS ENUM (
    'email_gmail', 'slack_webhook', 'kakao_bizmessage', 'discord_webhook',
    'telegram_bot', 'app_push_fcm', 'app_push_apns', 'in_app_web_notification'
);

CREATE TYPE notification_delivery_status_enum AS ENUM (
    'pending_dispatch', 'dispatched_to_provider', 'delivered_to_recipient',
    'failed_permanently', 'failed_temporarily_will_retry', 'opened_by_recipient',
    'clicked_by_recipient', 'error_invalid_address', 'user_opted_out_channel', 'unknown_status'
);

CREATE TYPE plan_key_enum AS ENUM (
    'free', 'basic', 'premium', 'team_basic', 'team_premium', 'enterprise', 'trial' -- 'trial' 추가
);

CREATE TYPE repo_access_level_enum AS ENUM (
    'owner', 'admin', 'maintainer', 'developer', 'viewer', 'guest'
);

CREATE TYPE repo_connection_status_enum AS ENUM (
    'pending', 'connected', 'disconnected', 'error', 'syncing'
);

CREATE TYPE repo_vcs_platform_enum AS ENUM (
    'github', 'gitlab', 'bitbucket', 'other'
);

CREATE TYPE repo_visibility_enum AS ENUM (
    'public', 'private', 'internal'
);

CREATE TYPE reward_status_enum AS ENUM (
    'active', 'used', 'expired', 'revoked'
);

CREATE TYPE snapshot_analysis_status_enum AS ENUM (
    'pending', 'queued', 'processing', 'completed', 'partial_success', 'failed', 'cancelled'
);

CREATE TYPE snapshot_trigger_event_enum AS ENUM (
    'webhook_push', 'manual_sync', 'scheduled_scan', 'initial_registration'
);

CREATE TYPE team_member_role_enum AS ENUM (
    'member', 'maintainer', 'admin', 'owner_surrogate'
);

CREATE TYPE user_account_type AS ENUM (
    'personal', 'team', 'org'
);

CREATE TYPE user_rule_action_type_enum AS ENUM (
    'prepend_to_title', 'append_to_body', 'require_keyword_in_title',
    'set_commit_type_prefix', 'add_issue_tracker_link'
);

CREATE TYPE user_rule_condition_type_enum AS ENUM (
    'file_path_pattern', 'change_type_is', 'min_lines_changed',
    'affected_function_name_matches', 'has_keyword_in_diff'
);