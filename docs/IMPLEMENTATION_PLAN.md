# ECS Scheduler 알림 배칭 구현 계획

## 현재 상황

- **서비스 수**: dev/stg 각 20개, 최대 50개 예정
- **문제점**:
  1. Slack Webhook Rate Limit (1 req/sec) → 알림 누락 가능
  2. 09:00/18:00에 20~50개 알림 폭주 → 채널 마비
  3. ECS API 동시 호출 → Throttling 가능성

---

## 목표 아키텍처

### 변경 전
```
EventBridge Scheduler → ECS UpdateService
CloudTrail → EventBridge Rule → SNS → Lambda → Slack (개별 알림 N개)
```

### 변경 후
```
EventBridge Scheduler (5분 분산) → ECS UpdateService
CloudTrail → EventBridge Rule → SQS (배칭) → Lambda → Slack (요약 알림 1개)
```

---

## 변경 사항 요약

| 구분 | 현재 | 변경 후 |
|------|------|---------|
| 스케줄 실행 | 정확한 시간 | 5분 내 분산 (flexible_time_window) |
| 알림 전달 | SNS → Lambda | SQS → Lambda (batch) |
| 알림 형태 | 개별 알림 N개 | 요약 알림 1개 |
| Lambda 트리거 | SNS (즉시) | SQS (5분 대기 또는 10개 모임) |

---

## 구현 단계

### Phase 1: ECS Scheduler 시간 분산 적용

**파일**: `modules/ecs-scheduler/main.tf`

**변경 내용**:
```hcl
# 변경 전
flexible_time_window {
  mode = "OFF"
}

# 변경 후
flexible_time_window {
  mode                      = "FLEXIBLE"
  maximum_window_in_minutes = 5
}
```

**효과**:
- 50개 서비스가 09:00~09:05 사이에 분산 실행
- ECS UpdateService API throttling 방지

---

### Phase 2: slack-notifier 모듈 재구성

**파일**: `modules/slack-notifier/main.tf`

#### 2-1. SNS → SQS로 변경

```hcl
# 새로 추가
resource "aws_sqs_queue" "alerts" {
  name                       = "${var.name_prefix}-alerts-${var.environment}"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 3600  # 1시간
}

# EventBridge Target을 SQS로 변경
resource "aws_cloudwatch_event_target" "send_to_sqs" {
  rule      = aws_cloudwatch_event_rule.ecs_update_service.name
  target_id = "SendToSQS"
  arn       = aws_sqs_queue.alerts.arn
}
```

#### 2-2. Lambda 트리거를 SQS Batch로 변경

```hcl
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn                   = aws_sqs_queue.alerts.arn
  function_name                      = aws_lambda_function.slack_notifier.arn
  batch_size                         = 10              # 최대 10개씩 처리
  maximum_batching_window_in_seconds = 300             # 5분 대기
  enabled                            = true
}
```

**동작 방식**:
- 메시지가 10개 모이면 즉시 Lambda 실행
- 또는 5분(300초) 지나면 모인 메시지들로 Lambda 실행
- 둘 중 먼저 충족되는 조건으로 트리거

---

### Phase 3: Lambda 함수 수정

**파일**: `modules/slack-notifier/lambda/index.py`

**변경 내용**: 배치 메시지 처리 + 요약 알림 생성

```python
def handler(event, context):
    # SQS에서 여러 메시지를 배치로 받음
    records = event.get('Records', [])

    results = []
    for record in records:
        # 각 CloudTrail 이벤트 파싱
        body = json.loads(record['body'])
        detail = body.get('detail', {})
        # ... 파싱 로직
        results.append({
            'service': service_name,
            'action': action,
            'status': status,
            'error': error_message
        })

    # 요약 메시지 생성 및 전송
    send_summary_to_slack(results)
```

---

### Phase 4: 기존 SNS 리소스 정리

**삭제할 리소스**:
- `aws_sns_topic.alerts`
- `aws_sns_topic_subscription.slack`
- `aws_lambda_permission.allow_sns`
- `aws_sns_topic_policy.allow_eventbridge`

---

## 예상 알림 형태

### 변경 전 (20개 개별 알림)
```
✅ ECS Scheduling Succeeded
Service: nestjs
Action: Scale Up (→ 1)
...

✅ ECS Scheduling Succeeded
Service: python-api
Action: Scale Up (→ 1)
...

(... 18개 더 ...)
```

### 변경 후 (1개 요약 알림)
```
📊 ECS Scheduled Scaling Summary
Time: 2024-01-15 09:00~09:05 KST
Environment: dev

┌─────────────────┬────────────┬──────────┐
│ Service         │ Action     │ Status   │
├─────────────────┼────────────┼──────────┤
│ nestjs          │ Scale Up   │ ✅       │
│ python-api      │ Scale Up   │ ✅       │
│ worker-service  │ Scale Up   │ ✅       │
│ frontend        │ Scale Up   │ ❌ Error │
│ ... (16 more)   │ Scale Up   │ ✅       │
└─────────────────┴────────────┴──────────┘

Total: 19 succeeded, 1 failed

❌ Failures:
• frontend: ResourceNotFoundException - Service not found
```

---

## 작업 순서

1. [ ] Phase 1: `ecs-scheduler` 모듈에 flexible_time_window 적용
2. [ ] Phase 2-1: `slack-notifier`에 SQS 리소스 추가
3. [ ] Phase 2-2: Lambda SQS 트리거 설정
4. [ ] Phase 3: Lambda 함수 배치 처리 로직으로 수정
5. [ ] Phase 4: 기존 SNS 리소스 제거
6. [ ] 테스트: dev 환경에서 검증
7. [ ] stg 환경 적용

---

## 롤백 계획

문제 발생 시:
1. `flexible_time_window`를 `OFF`로 변경
2. SQS 트리거 비활성화
3. SNS 리소스 복구 (git revert)

---

## 예상 비용 변화

| 서비스 | 변경 전 | 변경 후 |
|--------|---------|---------|
| SNS | $0.50/월 | $0 |
| SQS | $0 | ~$1/월 (Free tier 내) |
| Lambda | 동일 | 동일 (호출 수 감소) |

**총 비용 변화**: 거의 없음 (SQS Free tier: 월 100만 요청)

---

## 다음 단계

이 계획이 괜찮으시면 Phase 1부터 구현을 시작하겠습니다.
