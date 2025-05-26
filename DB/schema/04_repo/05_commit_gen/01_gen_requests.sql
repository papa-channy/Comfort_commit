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
    repo_id id NOT NULL REFERENCES repo_main(repo_id) ON DELETE CASCADE, -- 대상 저장소 (repo_main.repo_id 참조)

    -- 요청의 기준이 되는 스냅샷 정보
    source_snapshot_uuid id NOT NULL REFERENCES code_snapshots(snapshot_id) ON DELETE RESTRICT,
    -- 이 커밋 생성 요청의 분석 대상이 되는 원본 코드 스냅샷 (code_snapshots.snapshot_id 참조)
    -- ON DELETE RESTRICT: 커밋 생성 요청이 참조하는 스냅샷은 임의로 삭제할 수 없도록 제한

    -- 주요 변경 파일/요소 식별 정보 (스코핑 전 단계 또는 대표 변경 사항)
    -- 이 부분은 여러 파일/요소가 될 수 있으므로, 별도 매핑 테이블이나 JSONB로 관리 가능. MVP에서는 주요 파일 1개로 단순화 가능.
    primary_changed_file_instance_uuid id REFERENCES snapshot_file_instances(snapshot_file_uuid) ON DELETE SET NULL,
    -- 요청의 주된 분석 대상이 된 파일 인스턴스 (선택적, 스코핑 결과로 대체 가능)

    -- LLM 호출 및 생성 프로세스 상태 관리
    request_status request_status_enum DEFAULT 'PENDING', -- 현재 요청 처리 상태 (04_repo_module/00_repo_enums_and_types.sql 정의 예정)
                                                         -- 예: 'PENDING', 'SCOPING_STATIC', 'SCOPING_EMBEDDING', 'GENERATING_TECH_DESC', 'TECH_DESC_READY', 'GENERATING_COMMIT_MSG', 'COMMIT_MSG_READY', 'USER_REVIEW', 'COMPLETED', 'FAILED', 'CANCELLED'
    error_message TEXT,                                  -- 오류 발생 시 메시지

    -- 1차 LLM 호출 (기술 설명서 생성) 관련 컨텍스트 참조 uuid
    -- 실제 스코핑 결과는 `scoping_results` 테이블에 저장되고, 이 테이블에서는 해당 결과셋 uuid를 참조할 수 있음.
    scoping_result_uuid id, -- REFERENCES scoping_results(scoping_run_uuid) ON DELETE SET NULL, (04_scoping_results.sql 정의 후 FK 설정)
                            -- 1, 2차 스코핑 결과로 확정된 분석 대상 함수/파일 목록 세트 uuid

    readme_content_uuid id, -- REFERENCES generated_contents(content_uuid) ON DELETE SET NULL, (README 요약본 저장 테이블 참조, 추후 정의)
                            -- 사용된 README 요약본의 uuid (별도 콘텐츠 관리 테이블 필요 시) 또는 직접 저장 (아래 `context_references_json`)

    -- 2차 LLM 호출 (커밋 메시지 생성) 관련 컨텍스트 참조 uuid
    -- 생성된 기술 설명서는 `generated_technical_descriptions` 테이블에 저장되고, 여기서는 주요 설명서 uuid 목록을 참조.
    -- 사용된 Diff 조각은 `file_diff_fragments` 테이블에 저장되고, 여기서는 주요 Diff 조각 uuid 목록을 참조.
    context_references_json JSONB,
    -- 예: {
    --   "technical_description_uuids": ["id1", "id2"], (참조: 05_generated_technical_descriptions.sql)
    --   "diff_fragment_uuids": ["id_a", "id_b"], (참조: 04_repo_module/02_code_snapshots/03_file_diff_fragments.sql)
    --   "file_analysis_metric_uuids_for_llm": ["metric_id_x"], (참조: 04_repo_module/03_files/03_file_analysis_metrics.sql)
    --   "relevant_code_element_relation_uuids": ["relation_id_y"], (참조: 04_repo_module/04_code_elements/03_code_element_relations.sql)
    --   "custom_commit_rule_uuid": "rule_id_z", (참조: 05_customization_and_rules_module)
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
COMMENT ON COLUMN commit_generation_requests.user_id IS '요청을 시작한 사용자의 id (user_info.id 참조)입니다.';
COMMENT ON COLUMN commit_generation_requests.session_uuid IS '요청이 발생한 사용자 세션의 id (user_session.session_uuid 참조, 선택적)입니다.';
COMMENT ON COLUMN commit_generation_requests.repo_id IS '커밋 생성 대상 저장소의 id (repo_main.repo_id 참조)입니다.';
COMMENT ON COLUMN commit_generation_requests.source_snapshot_uuid IS '분석의 기준이 되는 코드 스냅샷의 id (code_snapshots.snapshot_id 참조)입니다.';
COMMENT ON COLUMN commit_generation_requests.primary_changed_file_instance_uuid IS '요청의 주된 분석 대상이 된 파일 인스턴스의 id (snapshot_file_instances.snapshot_file_uuid 참조, 선택적)입니다.';
COMMENT ON COLUMN commit_generation_requests.request_status IS '현재 커밋 생성 요청의 처리 상태입니다 (04_repo_module/00_repo_enums_and_types.sql 정의된 request_status_enum 값).';
COMMENT ON COLUMN commit_generation_requests.error_message IS '요청 처리 중 오류가 발생한 경우 해당 오류 메시지를 저장합니다.';
COMMENT ON COLUMN commit_generation_requests.scoping_result_uuid IS '이 요청에 사용된 스코핑 결과 세트의 uuid 참조입니다 (scoping_results.scoping_run_uuid 참조 예정).';
COMMENT ON COLUMN commit_generation_requests.readme_content_uuid IS 'LLM 입력에 사용된 README 요약본의 uuid 참조입니다 (별도 콘텐츠 관리 테이블 정의 필요 시).';
COMMENT ON COLUMN commit_generation_requests.context_references_json IS '커밋 메시지 생성(2차 LLM 호출)에 사용된 다양한 컨텍스트 요소들의 참조 uuid를 JSONB 형태로 저장합니다.';
COMMENT ON COLUMN commit_generation_requests.generated_commit_content_uuid IS 'LLM이 생성한 커밋 메시지 초안의 uuid 참조입니다 (generated_commit_contents.generated_content_uuid 참조 예정).';
COMMENT ON COLUMN commit_generation_requests.finalized_commit_uuid IS '사용자가 최종 확정한 커밋의 uuid 참조입니다 (finalized_commits.finalized_commit_id 참조 예정).';
COMMENT ON COLUMN commit_generation_requests.request_timestamp IS '요청이 시스템에 접수된 시각입니다.';
COMMENT ON COLUMN commit_generation_requests.completion_timestamp IS '요청 처리가 최종적으로 완료된 시각입니다.';
COMMENT ON COLUMN commit_generation_requests.user_preferences_json IS '요청 시 적용된 사용자 선호도 설정 (커밋 스타일, 언어 등)을 JSONB로 저장합니다.';
COMMENT ON COLUMN commit_generation_requests.processing_metadata IS '요청 처리 과정에서 발생한 내부 메타데이터 (단계별 소요 시간, 사용 모델 등)를 JSONB로 저장합니다.';
COMMENT ON COLUMN commit_generation_requests.created_at IS '이 요청 레코드가 데이터베이스에 처음 생성된 시각입니다.';
COMMENT ON COLUMN commit_generation_requests.updated_at IS '이 요청 레코드 정보가 마지막으로 수정된 시각입니다.';


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
