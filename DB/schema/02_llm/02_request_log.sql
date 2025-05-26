-- =====================================================================================
-- 파일: 02_llm_request_log.sql
-- 모듈: 02_llm_module (LLM 연동 관리 모듈)
-- 설명: LLM API 호출과 관련된 모든 요청 및 응답 정보를 기록합니다.
-- 대상 DB: PostgreSQL Primary RDB (LLM 사용량 및 성능 분석 데이터)
-- 파티셔닝: 필수 (`created_at` 기준 RANGE 파티셔닝, MVP: 월 단위 수동 생성, 스케일업: 일 단위 자동 생성).
-- MVP 중점사항: 핵심 요청/응답 메타데이터, 토큰/비용 정보, 파티셔닝 기본 설정, 필수 인덱스. prompt/completion 원문 DB 저장(길이 제한 및 PII 마스킹 정책 적용).
-- 스케일업 고려사항: RLS, 파티션 자동 생성/관리 (pg_partman), Cold Storage로의 데이터 아카이빙, prompt/completion 원문 외부(Loki/S3) 저장 및 참조 uuid 관리, OpenSearch 연동 (로그 검색/분석).
-- =====================================================================================

CREATE TABLE llm_request_log (
  uuid BIGSERIAL,                                           -- 내부 자동 증가 uuid (PK는 복합키의 일부)
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, -- 로그 생성 시각 (파티셔닝 키)

  id id REFERENCES user_info(id) ON DELETE SET NULL,-- 요청을 발생시킨 사용자 (탈퇴 시 NULL로 익명화)
  key_uuid INT REFERENCES llm_key_config(uuid) ON DELETE SET NULL, -- 사용된 API 키 (llm_key_config.uuid 참조)

  request_correlation_uuid id DEFAULT gen_random_id(),  -- 단일 사용자 요청 내 여러 LLM 호출을 그룹핑하기 위한 uuid (예: 기술문서 생성 -> 커밋 메시지 생성)
  tag TEXT,                                               -- 요청의 목적 또는 분류 태그 (예: 'commit_message_draft', 'code_summary_for_review', 'error_analysis_v1')
  stage TEXT,                                             -- 요청이 발생한 시스템 내 단계 (예: 'initial_generation', 'refinement_pass_1', 'user_feedback_correction')

  provuuider TEXT NOT NULL,                                 -- 사용된 LLM 제공자 (llm_key_config.provuuider와 일치)
  model TEXT NOT NULL,                                    -- 사용된 LLM 모델명 (llm_key_config.model_served와 일치 또는 하위 모델)
  params JSONB,                                           -- LLM 호출 시 사용된 파라미터 (temperature, top_p, max_tokens 등)

  -- 토큰 및 비용 정보
  -- tokens[1]=prompt_tokens, tokens[2]=completion_tokens, tokens[3]=total_tokens
  tokens INT[] CHECK (array_length(tokens, 1) = 3),
  -- cost_per_million_tokens[1]=input_cost_usd, cost_per_million_tokens[2]=output_cost_usd (USD 기준, 백만 토큰당 단가)
  cost_per_million_tokens NUMERIC[] CHECK (array_length(cost_per_million_tokens, 1) = 2),
  cost_usd NUMERIC(10,7),                                 -- 해당 요청으로 발생한 총 비용 (USD). 애플리케이션에서 계산: (tokens[1]/1e6 * cost_per_million_tokens[1]) + (tokens[2]/1e6 * cost_per_million_tokens[2])

  -- 요청 및 응답 내용
  -- MVP: DB에 직접 저장 (길이 제한 및 PII 마스킹 정책 적용 필수).
  -- 스케일업: Loki/S3 등 외부 저장소로 이전하고, 여기에는 external_prompt_ref_uuid, external_completion_ref_uuid 와 같은 참조 uuid만 저장.
  prompt TEXT,                                            -- LLM에 전달된 실제 프롬프트 (필요시 길이 제한 및 PII 마스킹 처리)
  completion TEXT,                                        -- LLM으로부터 받은 실제 응답 (필요시 길이 제한)

  -- 결과 및 성능
  success BOOLEAN,                                        -- LLM API 호출 성공 여부
  error_message TEXT,                                     -- 실패 시 오류 메시지
  error_code TEXT,                                        -- 실패 시 오류 코드 (Provuuider 자체 코드 또는 HTTP 상태 코드)
  duration_ms INT,                                        -- LLM API 호출 및 응답 수신까지 총 소요 시간 (밀리초)
  user_latency_ms INT,                                    -- 사용자 관점에서 해당 기능을 사용하는 데 체감한 총 지연 시간 (LLM 호출 시간 포함)

  PRIMARY KEY (uuid, created_at)                            -- 파티션 테이블의 PK는 파티션 키를 포함해야 함
)
PARTITION BY RANGE (created_at);

COMMENT ON TABLE llm_request_log IS 'LLM API 호출과 관련된 모든 요청, 응답, 비용, 성능 정보를 기록합니다. 파티셔닝을 통해 대용량 로그를 관리합니다.';
COMMENT ON COLUMN llm_request_log.uuid IS 'LLM 요청 로그의 내부 자동 증가 uuid입니다. created_at과 함께 복합 기본 키를 구성합니다.';
COMMENT ON COLUMN llm_request_log.created_at IS '로그가 기록된 시각이며, 테이블 파티셔닝의 기준 키입니다.';
COMMENT ON COLUMN llm_request_log.id IS 'LLM 요청을 트리거한 사용자의 id입니다. 사용자 탈퇴 시 NULL로 설정됩니다.';
COMMENT ON COLUMN llm_request_log.key_uuid IS 'LLM 호출에 사용된 API 키의 uuid (llm_key_config.uuid 참조)입니다.';
COMMENT ON COLUMN llm_request_log.request_correlation_uuid IS '하나의 사용자 액션으로 인해 발생하는 여러 단계의 LLM 호출들을 논리적으로 묶기 위한 id입니다.';
COMMENT ON COLUMN llm_request_log.tag IS 'LLM 요청의 비즈니스 목적이나 사용된 기능의 태그입니다 (예: commit_message_generation).';
COMMENT ON COLUMN llm_request_log.stage IS 'LLM 호출이 발생한 시스템 내부의 주요 단계를 나타냅니다 (예: 스코핑, 1차 기술 설명서 생성, 2차 커밋 메시지 생성).';
COMMENT ON COLUMN llm_request_log.provuuider IS 'LLM API를 제공한 회사의 식별자입니다 (예: fireworks, openai).';
COMMENT ON COLUMN llm_request_log.model IS '호출에 사용된 특정 LLM 모델의 이름입니다.';
COMMENT ON COLUMN llm_request_log.params IS 'LLM API 호출 시 사용된 하이퍼파라미터들을 JSONB 형태로 저장합니다 (예: {"temperature": 0.7, "max_tokens": 512}).';
COMMENT ON COLUMN llm_request_log.tokens IS 'LLM API 호출에서 사용된 토큰 수 배열입니다: [prompt_tokens, completion_tokens, total_tokens].';
COMMENT ON COLUMN llm_request_log.cost_per_million_tokens IS '사용된 모델의 백만 토큰당 비용 배열입니다 (USD 기준): [input_cost_per_million, output_cost_per_million].';
COMMENT ON COLUMN llm_request_log.cost_usd IS '해당 LLM 요청 1건으로 인해 발생한 총 비용 (USD) 입니다. 애플리케이션 레벨에서 토큰 수와 단가를 기반으로 계산되어 저장됩니다.';
COMMENT ON COLUMN llm_request_log.prompt IS 'LLM에 전달된 프롬프트 원문입니다. MVP에서는 DB에 직접 저장하되, 길이 제한 및 개인 식별 정보(PII) 마스킹 정책 적용이 필수입니다. 스케일업 시 외부 저장소로 이전 고려 대상입니다.';
COMMENT ON COLUMN llm_request_log.completion IS 'LLM으로부터 받은 응답 원문입니다. MVP에서는 DB에 직접 저장하되, 길이 제한 적용을 고려합니다. 스케일업 시 외부 저장소로 이전 고려 대상입니다.';
COMMENT ON COLUMN llm_request_log.success IS 'LLM API 호출이 성공적으로 완료되었는지 여부입니다.';
COMMENT ON COLUMN llm_request_log.error_message IS 'LLM API 호출 실패 시 반환된 오류 메시지입니다.';
COMMENT ON COLUMN llm_request_log.error_code IS 'LLM API 호출 실패 시 Provuuider가 반환한 오류 코드 또는 HTTP 상태 코드입니다.';
COMMENT ON COLUMN llm_request_log.duration_ms IS 'LLM API를 호출하고 응답을 받기까지 순수하게 소요된 시간 (밀리초 단위)입니다.';
COMMENT ON COLUMN llm_request_log.user_latency_ms IS '사용자 요청 시작부터 LLM 응답을 포함한 최종 결과를 받기까지 사용자가 체감한 총 지연 시간입니다 (선택적).';


-- llm_request_log 테이블 파티션 생성 예시 (MVP 단계에서는 수동으로 몇 개 생성, 스케일업 시 자동화)
-- 예시: 2025년 5월 파티션
-- CREATE TABLE llm_request_log_y2025m05 PARTITION OF llm_request_log
-- FOR VALUES FROM ('2025-05-01') TO ('2025-06-01');
-- (참고: 실제 운영 시에는 pg_partman 등을 사용하여 파티션 자동 생성 및 관리가 권장됩니다.)

-- 인덱스
CREATE INDEX uuidx_llm_request_log_id_created_at ON llm_request_log(id, created_at DESC) WHERE id IS NOT NULL; -- 특정 사용자의 최근 LLM 요청 조회
CREATE INDEX uuidx_llm_request_log_key_uuid_created_at ON llm_request_log(key_uuid, created_at DESC) WHERE key_uuid IS NOT NULL; -- 특정 API 키로 발생한 최근 요청 조회
CREATE INDEX uuidx_llm_request_log_model_created_at ON llm_request_log(model, created_at DESC); -- 특정 모델 사용 요청 조회
CREATE INDEX uuidx_llm_request_log_success_created_at ON llm_request_log(success, created_at DESC); -- 성공/실패 요청 필터링
CREATE INDEX uuidx_llm_request_log_tag_created_at ON llm_request_log(tag, created_at DESC); -- 특정 태그 요청 조회
CREATE INDEX uuidx_llm_request_log_correlation_uuid ON llm_request_log(request_correlation_uuid) WHERE request_correlation_uuid IS NOT NULL; -- 연관 요청 그룹 조회
-- created_at은 PK의 일부이므로 개별 인덱스 불필요.

-- 스케일업 고려사항 주석:
-- COMMENT ON TABLE llm_request_log IS '(스케일업 시: 프롬프트/응답 외부 저장 후 external_prompt_ref_uuid, external_completion_ref_uuid 컬럼 추가. 캐싱 및 재사용성 향상을 위해 original_request_uuid, embedding_hash, reuse_flag, vector_similarity_score 등의 컬럼 추가 고려.)';