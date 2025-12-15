# ECS Scheduler 알림 배칭 구현 완료 보고서

**작성일**: 2025-12-13
**상태**: 완료

---

## 개요

ECS 서비스 스케줄링 알림을 개별 전송에서 배칭 방식으로 변경하여, 다수의 서비스(20~50개)가 동시에 스케줄링될 때 발생하는 알림 폭주 문제를 해결했습니다.

---

## 변경 사항 요약

### 아키텍처 변경

```
[변경 전]
EventBridge Scheduler → ECS UpdateService
CloudTrail → EventBridge Rule → SNS → Lambda → Slack (개별 알림 N개)

[변경 후]
EventBridge Scheduler (5분 분산) → ECS UpdateService
CloudTrail → EventBridge Rule → SQS (배칭) → Lambda → Slack (요약 알림 1개)
```

### 변경된 파일

| 파일 | 변경 내용 |
|------|----------|
| `modules/ecs-scheduler/variables.tf` | `flexible_time_window_minutes` 변수 추가 |
| `modules/ecs-scheduler/main.tf` | flexible_time_window 동적 설정 적용 |
| `modules/slack-notifier/variables.tf` | `batch_size`, `batching_window_seconds` 변수 추가 |
| `modules/slack-notifier/main.tf` | SNS → SQS 변경, Lambda Event Source Mapping 추가 |
| `modules/slack-notifier/outputs.tf` | SNS output → SQS output 변경 |
| `modules/slack-notifier/lambda/index.py` | 배치 처리 및 요약 알림 로직 구현 |

---

## 상세 변경 내용

### 1. ecs-scheduler 모듈

#### 새로운 변수

```hcl
variable "flexible_time_window_minutes" {
  description = "Maximum window in minutes for flexible scheduling (0 = OFF, 1-60 = FLEXIBLE)"
  type        = number
  default     = 5
}
```

#### 스케줄 설정 변경

```hcl
flexible_time_window {
  mode                      = var.flexible_time_window_minutes > 0 ? "FLEXIBLE" : "OFF"
  maximum_window_in_minutes = var.flexible_time_window_minutes > 0 ? var.flexible_time_window_minutes : null
}
```

**효과**: 50개 서비스가 09:00~09:05 사이에 자동 분산 실행되어 ECS API throttling 방지

---

### 2. slack-notifier 모듈

#### 새로운 변수

```hcl
variable "batch_size" {
  description = "Maximum number of messages to batch before sending to Slack"
  type        = number
  default     = 10
}

variable "batching_window_seconds" {
  description = "Maximum time in seconds to wait for batching messages"
  type        = number
  default     = 300  # 5분
}
```

#### 리소스 변경

| 삭제됨 | 추가됨 |
|--------|--------|
| `aws_sns_topic.alerts` | `aws_sqs_queue.alerts` |
| `aws_sns_topic_subscription.slack` | `aws_sqs_queue_policy.allow_eventbridge` |
| `aws_lambda_permission.allow_sns` | `aws_iam_role_policy.lambda_sqs` |
| `aws_sns_topic_policy.allow_eventbridge` | `aws_lambda_event_source_mapping.sqs_trigger` |
| `aws_cloudwatch_event_target.send_to_sns` | `aws_cloudwatch_event_target.send_to_sqs` |

#### Lambda Event Source Mapping 설정

```hcl
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn                   = aws_sqs_queue.alerts.arn
  function_name                      = aws_lambda_function.slack_notifier.arn
  batch_size                         = var.batch_size        # 최대 10개
  maximum_batching_window_in_seconds = var.batching_window_seconds  # 5분 대기
  enabled                            = true
}
```

**트리거 조건**:
- 메시지 10개 도달 → 즉시 Lambda 호출
- 5분 경과 → 현재까지 모인 메시지로 Lambda 호출

---

### 3. Lambda 함수 변경

#### 주요 변경점

1. **SQS 배치 처리**: `event['Records']`에서 여러 메시지를 배열로 받아 처리
2. **요약 알림 생성**: 모든 서비스 결과를 하나의 테이블 형태로 정리
3. **성공/실패 구분**: 색상 및 아이콘으로 상태 구분
4. **환경 변수 추가**: `ENVIRONMENT` 변수로 환경 표시

#### 알림 형태 예시

**모두 성공 시**:
```
✅ ECS Scheduled Scaling Completed

Environment: DEV
Total Services: 20 (20 succeeded, 0 failed)

Services:
✅ `nestjs` - Scale Up (-> 1)
✅ `python-api` - Scale Up (-> 1)
✅ `worker` - Scale Up (-> 1)
... (17 more)

Time: 2025-12-13 09:05:00 KST
```

**일부 실패 시**:
```
⚠️ ECS Scheduled Scaling Partially Completed

Environment: DEV
Total Services: 20 (19 succeeded, 1 failed)

Services:
✅ `nestjs` - Scale Up (-> 1)
✅ `python-api` - Scale Up (-> 1)
❌ `frontend` - Scale Up (-> 1)
...

❌ Failure Details:
- `frontend`: ServiceNotFoundException - Service not found

Time: 2025-12-13 09:05:00 KST
```

---

## 검증 결과

```bash
$ terraform fmt -recursive
# (출력 없음 - 포맷 정상)

$ terraform validate
Success! The configuration is valid.
```

---

## 배포 단계

### 1. dev 환경 배포

```bash
cd environments/dev
terraform init
terraform plan
terraform apply
```

### 2. stg 환경 배포

```bash
cd environments/stg
terraform init
terraform plan
terraform apply
```

---

## 주의사항

### 기존 리소스 삭제

`terraform apply` 시 다음 리소스가 삭제됩니다:
- `aws_sns_topic.alerts`
- `aws_sns_topic_subscription.slack`
- `aws_lambda_permission.allow_sns`
- `aws_sns_topic_policy.allow_eventbridge`

### State 변경

기존 SNS 기반 리소스가 SQS 기반으로 교체되므로, `terraform plan` 출력을 반드시 확인하세요.

---

## 롤백 방법

문제 발생 시 Git에서 이전 커밋으로 되돌린 후 재배포:

```bash
git revert HEAD
cd environments/dev && terraform apply
cd environments/stg && terraform apply
```

---

## 기대 효과

| 항목 | 변경 전 | 변경 후 |
|------|---------|---------|
| 알림 수 (20개 서비스 기준) | 20개 | 1개 |
| Slack Rate Limit 이슈 | 발생 가능 | 해결 |
| ECS API Throttling | 발생 가능 | 해결 (5분 분산) |
| 알림 가독성 | 낮음 (개별 알림) | 높음 (요약 테이블) |

---

## 추가 개선 가능 사항

1. **Dead Letter Queue (DLQ)**: SQS 처리 실패 시 재시도를 위한 DLQ 추가
2. **CloudWatch Alarm**: Lambda 실패 시 별도 알림
3. **Scale Up/Down 그룹핑**: 같은 배치 내에서도 Scale Up/Down을 분리하여 표시

---

## 관련 문서

- [IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md) - 구현 계획
- [QA_SQS_BATCHING.md](./QA_SQS_BATCHING.md) - SQS 배칭 Q&A
