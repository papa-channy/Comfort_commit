# Comfort Commit - Embedding Storage & Versioning Architecture

**최종 수정일:** 2025-05-26

---

## 📦 개요

Comfort Commit은 코드 의미 분석 및 커밋 자동화 시스템으로서, 대규모 코드 스냅샷 및 임베딩 데이터를 안정적이고 확장성 있게 저장하기 위해 **운영 DB와 임베딩 DB를 분리**하여 관리합니다.

이 문서는 해당 구조의 설계 목적, 처리 방식, 스케줄링 전략, 그리고 데이터 저장 정책을 기술합니다.

---

## 🧱 DB 아키텍처 개요

| 구분 | 목적 | 주요 테이블 | 저장소 |
|------|------|-------------|--------|
| 서비스 DB (Main) | 사용자 정보, 세션, 커밋 요청 | `user_info`, `commit_generation_requests`, `snapshot_file_instances` | PostgreSQL (port 5432) |
| 임베딩 DB (Embedding) | 의미 임베딩 벡터, 코드 유사도, 코드 흐름 기록 | `code_element_embeddings`, `snapshot_code_element_instances` 등 | PostgreSQL (port 5433, pgvector 포함) |

---

## 🧠 임베딩 저장 방식 및 버전 관리

- 모든 코드 요소(`element_instance_id`)에 대해 임베딩 결과를 계산하여 저장
- **덮어쓰기 없음**: 매번 결과를 `jsonb` 필드에 **버전 단위로 누적 저장**
- 저장 방식 예시 (`code_element_embeddings.result_versions`):

```json
{
  "v2024-05-01": [0.12, 0.56, ..., 0.88],
  "v2024-06-01": [0.13, 0.57, ..., 0.85]
}
```

- 모델 이름, 차원 수, 생성일 등은 개별 필드(`embedding_model_name`, `vector_dimensions`, `generated_at`)로 별도 저장

---

## 🔁 이전 → 분리 DB로 이동 전략

| 구분 | 설명 |
|------|------|
| 파티셔닝 대상 | 로그성 테이블, 대용량 JSONB, 함수 인스턴스별 누적 임베딩 |
| 이동 주기 | `매일 / 매주 / 매월` 중 선택 → 전체 고객 트래픽 패턴에 따라 유동 적용 |
| 처리 방식 | Python에서 스냅샷 기준으로 누적된 데이터를 불러와, 별도 컨테이너 PostgreSQL에 bulk insert |
| 데이터 누적 조건 | `embedding_version` 또는 `generated_at` 기준으로 신규 여부 판단 후 이동 |

---

## 🛡️ 보안 및 자산화 전략

- **서비스용 DB ↔ 분석용 DB 분리**로 보안 강화
- 임베딩 데이터는 고객 코드에서 유래했더라도 **비가역적 추상 데이터이므로 Comfort Commit 자산으로 분류 가능**
- 향후 분석, 리팩토링 추천, 모델 학습 등에 활용

---

## 🔄 주기적 이동 예시 (cron)

```bash
# 예: 매주 월요일 새벽 3시 임베딩 데이터 이동
0 3 * * 1 /usr/bin/python3 /app/embedding/move_embeddings.py >> /var/log/embedding_cron.log 2>&1
```

또는 Celery/Argo/Airflow로 스케줄링 구성 가능

---

## ✅ 추가 고려 사항

- `embedding_model_name` 기준 파티션 구성 가능
- `vector_dimensions` → 분석 정확도/모델 성능 비교 연구 가능
- 모델별로 임베딩 테이블 분리도 가능 (Code2Vec, CodeBERT 등)

---

## ✍ 설계 요약

- ✅ 실시간 처리 대신 **비동기/예약 기반 ETL**
- ✅ DB 단위 격리로 **속도 + 보안 + 자산화** 달성
- ✅ 누적 저장을 통한 **임베딩 변화 흐름 분석** 구조 확보
