# Comfort_commit# Comfort Commit 시스템 설계서  
## 1. 프로젝트 개요 & 철학 (WHY)

### 1‑1. 배경 · 문제가치
| 기존 개발 현실 | Pain Point (정량 근거) |
| -------------- | ---------------------- |
| **컨텍스트 손실** — uuidE를 닫는 순간 “무엇을 왜 바꿨는가”가 머릿속에서 빠르게 사라짐 | 평균 3 시간 뒤 커밋 작성 시 변경 맥락 회상률 **< 35 %** |
| **낮은 커밋 품질** — `fix bug`, `update` 류 메시지 다발 | 코드 리뷰 “의도 파악 시간”이 전체 리뷰 시간의 **41 %** |
| **리뷰 과부하** — 파일·함수 스코프 뒤섞여 PR 검토 클릭수 폭증 | SaaS 리포 1 PR당 평균 **211 초** 소모 |
| **장소 제약** — 커밋 승인은 “사무실 PC 앞”에 묶여 있음 | 통근·이동 시간 **0 %** 활용 |

### 1‑2. Comfort Commit 비전
> **“코드 변경이 끝나는 순간, 당신의 ‘일상’ 속에서 커밋이 완결된다.”**

| 핵심 가치 | 구현 방식 | 기대 효과 |
| --------- | -------- | --------- |
| **일상 몰입 (Seamless Life‑flow)** | uuidE 종료 훅 감지 → 5 초 내 모바일 Push 링크 발송 → 사용자는 이동 중·퇴근 길에도 브라우저 한 화면에서 초안 수정·승인 | 사무실 복귀 없이 커밋 완료 → 업무 밀도 ↑, 퇴근 지연 ↓ |
| **맥락 보존 (Context Memory)** | AI가 변경 범위(파일·함수·심볼) 그래프화 → 요약 + 초안 메시지 즉시 제시 | “바꾼 직후” 검토로 기억 정착 효과, 지식 자산 장기 보존 |
| **보안 우선 (Security by Design)** | TLS 전구간 · AES‑256, 임베딩·로그 사내 DB 한정 | IP 유출 **0 %** 원칙 준수 |
| **재사용 지능 (Re‑use Intelligence)** | 사용자 수정본‑임베딩 캐시 → 유사도 ≥ 0.85면 LLM 호출 Skip | 인퍼런스 비용 ↓ 20 %, 지연 ↓ 35 % |

#### 사용 흐름 예시
코드 수정 → uuidE 저장 → VS Code 종료

2 초 뒤 Slack DM “📝 커밋 초안 검토” 도착

지하철 안에서 모바일 브라우저 열기
┌ 변경 요약 카드 │ AI 초안 │ diff │ 수정·승인 ┐

30 초 내 승인 → 자동 commit & push

로그 = Loki, 최종 메시지·벡터 = PostgreSQL·OpenSearch

---

## 2. 아키텍처 설계 원칙 (HOW)

| # | 원칙 | 기술 적용 · 운영 규칙 |
|---|------|----------------------|
| **P‑1 불변 코어** | Docker · Python 3.13 · PostgreSQL 16 · pgvector · FastAPI · JSONL 은 영구 불변<br>Elastic Layer는 붙였다 떼기 | 코드 이동/스케일 이동 시 리스크 최소화 |
| **P‑2 Seamless Life‑flow** | Hook → Mobile Push → Auto Commit 1 분 내 완결 | 사용자는 “코드 편집 ↔ 승인” 외 작업 0 |
| **P‑3 Security First** | OAuth → JWT → AES‑256 Refresh 저장, RBAC (action) 통제 | 모든 민감 데이터는 경계 내 & 암호화 |
| **P‑4 Observability by Default** | `trace_uuid`, `repo_uuid`, `user_uuid` 라벨을 시작부터 부여 → Loki · Prometheus · OpenSearch 자동 연결 | MTTR < 5 분 |
| **P‑5 Scale‑Out First** | API stateless, Celery/Redis/LLM Pool 노드는 코드 수정 없이 증설 | 글로벌 점심·퇴근 스파이크 대응 |
| **P‑6 Re‑use Intelligence** | 임베딩 캐시 유사도 0.85↑ hit → LLM 호출 Skip | 클라우드 비용, 지연 동시 절감 |
| **P‑7 Config‑as‑Runtime** | `plan_config.yml` 등 정책 파일을 핫 리로드 | 요금제·정책 변경 즉시 무중단 반영 |

### 원칙 체감 예시

| 시나리오 | 원칙 적용 | 결과 |
|----------|----------|------|
| **글로벌 트래픽 스파이크** | P‑5 HPA 10→60 replica | 응답 P95 < 3.8 s 유지 |
| **보안 감사 요구** | P‑3 · P‑4 action 로그 + trace_uuid | 30 초 내 원인 추적 |
| **요금제 정책 변경** | P‑7 config 핫 리로드 | 재배포 없이 즉시 반영 |
| **반복 커밋** | P‑6 임베딩 재사용 | LLM 비용 ↓ 20 %, 지연 ↓ 35 % |

---

## 3. 핵심 시스템 구성요소 — Fixed Kernel

| 계층 | 기술 & 버전 | 아키텍처 포인트 | 보안·운영 체크리스트 |
|------|-------------|-----------------|----------------------|
| **컨테이너** | **Docker 25** + docker‑compose v2 <br>(→ Helm/Kustomize 변환) | 이미지마다 **SBOM + Cosign 서명**<br>멀티 아키텍처(amd64/arm64) 빌드 | `read_only: true`, `rootless`, `seccomp=default` |
| **런타임** | **Python 3.13** + Poetry.lock | tomllib 내장, UTF‑8 default | `PYTHONHASHSEED=0` 고정, `uvloop` 옵션 |
| **Web API** | **FastAPI 1.4** + Uvicorn workers | Starlette ASGI = true async I/O<br>OpenAPI → 내부 SDK(py/js) 생성 | 모든 응답 헤더에 `trace_uuid`, `repo_uuid` |
| **RDBMS** | **PostgreSQL 16** | JSONB + Row‑Level Security, FTS GIST | pgbouncer pool, TLS in‑transit |
| **벡터** | **pgvector 0.8 (HNSW)**<br>Free→code2vec 512dim<br>Org→BERT 1536dim | HNSW M=16, ef_construction=200 | 배치 `REINDEX VECTOR` 크론 |
| **로깅 포맷** | **JSONL** (6 라벨 *svc,lvl,ts,id,repo,trace*) | tail‑f, S3 업로드, Loki 호환 | 민감 정보 RegExp 필터 |
| **시스템 로그** | **Loki 3.0** + S3 obj‑store | 라벨 인덱싱 저비용, Grafana alert | error율 >1 % → Slack #infra |
| **콘텐츠 로그** | **OpenSearch 3.0** + pgvector | plan prefix 색인, BM25 + HNSW | index‑level IAM |
| **토큰 모니터** | **@track_tokens** (tiktoken) | 30 µs 오버헤드, 비용·latency 로그 | AccessKey 그룹별 cost view |
| **패키지 레이어** | `api/ services/ models/ schemas/` | router→service→ORM 3‑hop DI | pytest fixture mock DB |

---

## 4. 유연 확장 계층 — Elastic Layer

| 카테고리 | Phase 0 (≤1 k DAU) | Phase 1 (~30 k) | Phase 2 (30 k–300 k) | **스케일 트리거** |
|----------|-------------------|-----------------|----------------------|-------------------|
| API Replica | Gunicorn×3 | Gunicorn×10 | K8s HPA→60 pod | CPU>65 % · RPS>500 |
| LLM Inference | OpenAI single‑key | vLLM (g5.xlarge)×2 | Spot A10G Pool AutoScale | 함수 QPS≥100 |
| 알림 큐 | BackgroundTask | Celery+Redis | Redis 3‑Shard | backlog>1 k |
| Redis Cache | Redis single | Redis Sentinel | MemoryDB Cluster | RT>20 ms |
| 색인 모델 | code2vec | code2vec+BERT 필드 | plan prefix 분리 | plan=org |
| CDN | – | CloudFront + R2 | Edge KV POP | Edge error율>2 % |
| 로그 보존 | Loki 7d | 30d+Glacier | 90d+S3 IA | Storage>1TB |
| 요금제 Hot‑Reload | plan_config YAML | Admin UI→Redis pub | Consul watch | 정책 commit |

---

## 5. 인증 & 권한 모델 — OAuth + RBAC(Action)

### 5‑1. 인증 플로우
1. **OAuth 2.0** (google) → auth_code
2. `user_info` UPSERT → `id`
3. **JWT** (Access 10 min / Refresh 30 day)
4. Refresh 토큰 AES‑256‑GCM 암호화 → `user_secret`
5. `/refresh` → Access 갱신, Refresh Rotation

### 5‑2. RBAC 스키마
```sql
role(role_uuid, name)
action(action_uuid, code)
role_action_map(role_uuid, action_uuid)
user_info(id, email, role_uuid)
```

### 5‑3. 권한 검사 유틸
```python
def require(action):
    def deco(fn):
        async def wrap(user, *a, **kw):
            if action not in user.permissions:
               raise HTTPException(403)
            return await fn(user,*a,**kw)
        return wrap
    return deco
```

### 5‑4. 감사 로그 & 모바일 보안
| 위협 | 방어 |
|------|------|
| 링크 탈취 | JWT TTL 10min + URI nonce |
| 기기 분실 | Refresh Rotation + revoke API |
| 세션 고정 | SameSite=strict 쿠키 |


---

## 6. 사용자 요금제 & 기능 분기
### 6‑1 | `plan_catalog` 마스터 테이블 + 시딩
```sql
-- ❶ 요금제 정의 (once-only)
CREATE TABLE plan_catalog (
  plan_key               TEXT PRIMARY KEY,        -- 'free','basic','premium','org'
  plan_label             TEXT NOT NULL,           -- UI 표시명
  monthly_price_usd      NUMERIC(6,2) NOT NULL,   -- $/유저  (org=0 → seat 단가가 아닌 패키지 가격)
  max_commits_per_day    INT,
  max_commits_per_month  INT,
  max_describes_per_month INT,
  max_uploads_per_day    INT,
  kakao_noti_remaining   INT,
  slack_enabled          BOOLEAN,
  ad_layer_enabled       BOOLEAN,
  instant_commit_generation BOOLEAN,
  save_commit_message    BOOLEAN,
  save_describe_enabled  BOOLEAN,
  commit_report_enabled  BOOLEAN,
  visualization_report_enabled BOOLEAN,
  prompt_personalization_enabled BOOLEAN,
  data_retention_days    INT,
  team_features_enabled  BOOLEAN,
  trial_days             INT,
  plan_order             INT UNIQUE,              -- UI 노출 순서
  is_team_plan           BOOLEAN DEFAULT FALSE
);

INSERT INTO plan_catalog
(plan_key,plan_label,monthly_price_usd,max_commits_per_day,max_commits_per_month,
 max_describes_per_month,max_uploads_per_day,kakao_noti_remaining,slack_enabled,
 ad_layer_enabled,instant_commit_generation,save_commit_message,save_describe_enabled,
 commit_report_enabled,visualization_report_enabled,prompt_personalization_enabled,
 data_retention_days,team_features_enabled,trial_days,plan_order,is_team_plan)
VALUES
-- FREE ─ 개인 체험
('free','Free',0,
 5,100,100,10,
 0,FALSE,
 TRUE,FALSE,TRUE,TRUE,
 FALSE,FALSE,FALSE,
 30,FALSE,0,1,FALSE),

-- BASIC ─ 소규모 팀/프리랜서
('basic','Basic',9,
 100,2000,2000,200,
 20,TRUE,
 FALSE,TRUE,TRUE,TRUE,
 TRUE,FALSE,FALSE,
 180,FALSE,14,2,FALSE),

-- PREMIUM ─ 좌석 단가 최상위 개별 유저
('premium','Premium',29,
 500,UNLIMITED,UNLIMITED,1000,
 200,TRUE,
 FALSE,TRUE,TRUE,TRUE,
 TRUE,TRUE,TRUE,
 365,FALSE,14,3,FALSE),

-- ORG ─ 엔터프라이즈 패키지 (좌석당이 아니라 조직 라이선스)
('org','Enterprise',0,      -- seat price 0 → 별도 계약
 UNLIMITED,UNLIMITED,UNLIMITED,UNLIMITED,
 1000,TRUE,
 FALSE,TRUE,TRUE,TRUE,
 TRUE,TRUE,TRUE,
 1825,TRUE,30,4,TRUE);
```

### 6‑2 | `user_plan` + `user_plan_history`
- FK 추가
ALTER TABLE user_plan
  ADD CONSTRAINT fk_user_plan_plan
  FOREIGN KEY(plan_key) REFERENCES plan_catalog(plan_key);

-- 변경 트리거(요약)
CREATE OR REPLACE FUNCTION log_plan_change() RETURNS trigger AS $$
BEGIN
  IF NEW.plan_key <> OLD.plan_key THEN
    INSERT INTO user_plan_history(
      id, old_plan_key, new_plan_key,
      old_plan_label, new_plan_label,
      old_price_usd, new_price_usd,
      was_trial, effective_from
    )
    SELECT OLD.id,
           OLD.plan_key, NEW.plan_key,
           (SELECT plan_label FROM plan_catalog WHERE plan_key=OLD.plan_key),
           (SELECT plan_label FROM plan_catalog WHERE plan_key=NEW.plan_key),
           (SELECT monthly_price_usd FROM plan_catalog WHERE plan_key=OLD.plan_key),
           (SELECT monthly_price_usd FROM plan_catalog WHERE plan_key=NEW.plan_key),
           OLD.is_trial_active,
           now();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_user_plan_change
BEFORE UPDATE ON user_plan
FOR EACH ROW EXECUTE FUNCTION log_plan_change();

### 6‑3 | 런‑타임 분기 예시
```python
@lru_cache
def load_plan_catalog():
    import yaml
    with open("config/plan_catalog.yml") as f:
        return yaml.safe_load(f)

def get_plan(user_uuid):
    row = db.fetchrow("SELECT plan_key FROM user_plan WHERE id=%s", user_uuid)
    return load_plan_catalog()[row['plan_key']]

def enforce_limit(user_uuid, feature, amount=1):
    plan = get_plan(user_uuid)
    limit = plan.get(feature)
    if limit and get_usage(user_uuid, feature)+amount > limit:
        raise HTTPException(429,f"{feature} 초과")
```

---

## 7. 로그 수집 & 데이터 분리 전략
| 데이터 타입 | 저장소 | TTL | 대표 Query |
|-------------|--------|-----|-----------|
| 시스템 로그 | Loki + S3 | 30 d | `rate_errors{{svc="api"}}` |
| 비즈 이벤트 | PostgreSQL `biz_event` | ∞ | 월별 KPI |
| 콘텐츠 로그 | OpenSearch `cc_{{plan}}_commit_log_YYYYMM` | Free 30 d / Org ∞ | KNN + BM25 |
| 임시 캐시 | Redis | 1‑4 h | diff preview |

---

## 8. AI 임베딩 & 유사도 검색
| 플랜 | 모델 | 차원 | 필드 | 재사용 기준 |
|------|------|------|------|-------------|
| Free/Basic | code2vec | 512 | `embedding_code2vec` | cos ≥ 0.85 |
| Premium/Org | BERT / text‑embedding‑3 | 1536 | `embedding_bert` | cos ≥ 0.90 |

### 8‑1 | 임베딩 파이프라인
1. 커밋 초안 → LLM 호출  
2. 함수 Top‑10 → code2vec 임베딩 → Top‑3 확정  
3. pgvector KNN 검사 → hit ≥ 0.85 ⇒ LLM Skip  
4. 최종 메시지 확정 → OpenSearch 색인  
5. Premium/Org 플랜은 BERT 임베딩 추가 색인

```python
field = "embedding_bert" if plan in {{ "premium","org" }} else "embedding_code2vec"
```

---

## 9. 전체 시스템 데이터 흐름 & 모듈 연결

uuidE 종료 이벤트 ──► FastAPI(api) ──► Pre‑process(prep/, scoping/)
│ │
│ └─► LLM Manager + @track_tokens
│ │
│ └─► Notification(slack/mobile)
│ │
│ ▼
└─► Loki(JSONL) ◄──────────── action_log ◄─ 모바일 승인
│
▼
Auto‑Commit(git add/commit/push)
│
┌────────── OpenSearch 색인(embedding) ◄── embedding_worker
│
└─ Grafana / OsDash / Prometheus ←─ trace_uuid 기반 집계

yaml
항상 세부 정보 표시

복사

* **trace_uuid** : API → Loki → OpenSearch 연결 키  
* **plan_key** : 색인 prefix·임베딩 필드 선택  
* **action_log** : RBAC 감사, 누가 언제 무엇을 수정

---

## 10. MVP 개발 우선순위 & 런‑업 로드맵

| 스프린트 | 산출물 | 제외 범위 |
|----------|--------|-----------|
| **S‑1 (주 1‑2)** | VSCode hook·FastAPI skeleton | 모바일 UI |
| **S‑2 (주 3‑4)** | diff → conv_df → clustering Top‑3<br>LLM manager + track_tokens | 팀 플랜·RBAC |
| **S‑3 (주 5‑6)** | code2vec 임베딩 PG 저장<br>Slack DM 링크<br>Free 플랜 catalog | BERT 모델 |
| **S‑4 (주 7‑8)** | 모바일 승인 RWD 페이지<br>git auto‑commit<br>Loki + Grafana | Celery·K8s HPA |
| **S‑5 (주 9)** | OAuth Login, AES‑refresh 저장<br>action_log + require() | SSO (SAML) |

* **MVP KPI** : 첫 커밋 작성 시간 **≥ 60 % 단축**, 오류 재시도 **< 1 %**

---

## 11. 운영·보안·확장 전략

### 11‑1 | SRE 관측 지표
| 지표 | 임계치 | 자동 조치 |
|------|--------|-----------|
| API P95 latency | 4 s | K8s HPA scale‑out |
| LLM fail_rate | 3 % | fallback_on_cache |
| Celery backlog | 1 k | worker spawn |
| DB replica lag | 2 s | 읽기 redirect |

### 11‑2 | 보안
* OAuth‑only, 비밀번호 미보관  
* Row‑Level Security (repo ACL)  
* Column AES‑256 (refresh_token, 결제정보)  
* CSP + HSTS + SameSite=strict 쿠키

### 11‑3 | 비용·스케일
| 리소스 | 알림 | 대응 |
|--------|------|------|
| LLM 비용 | 월 \$500 | key rotation·fine‑tune 캐시 |
| OpenSearch | 80 % storage | ILM hot→warm→cold |
| GPU Pool | Spot 중단 | disruption budget 30 s |

---

## 12. 결론 & 향후 확장

| 버전 | 기능 | 가치 지표 |
|------|------|-----------|
| **v1.0 GA** | Free/BASIC + 모바일 승인 | 커밋 작성 지연 60 %↓ |
| **v1.5** | Premium (BERT 임베딩) + Prompt personal | 유사 커밋 자동 채움 25 %↑ |
| **v2.0** | Org 패키지 + SSO + 전담 VPC | 보안·규제 시장 침투 |
| **v2.5** | Auto‑Refactor (AST + LLM) | 코드 건강 △, 부채 ↓ |
| **v3.0** | Commit Intelligence Graph API | 생태계 연동 확장 |

**Comfort Commit** 은 커밋‑지능 → 코드‑지능 → 조직‑지능 으로 진화하여  
개발자의 기억·시간을 보존하는 **개발경험 OS** 로 자리잡는다.
""")

path = pathlib.Path("/mnt/data/ComfortCommit_9-12.md")
path.write_text(md9_12, encoding="utf-8")