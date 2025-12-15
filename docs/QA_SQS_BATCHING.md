# Q&A: SQS 배칭을 통한 알림 통합 구조

## Q1. 각 Scheduler가 독립적으로 실행되는데 어떻게 알림을 모아서 처리할 수 있나요?

### 질문 배경
- 각 EventBridge Scheduler는 자신의 ECS 서비스만 UpdateService 호출
- Scheduler들은 서로의 존재를 모름
- 그런데 어떻게 여러 서비스의 알림을 모아서 처리할 수 있는지?

### 답변

**핵심: 두 개의 독립된 경로가 존재**

```
[경로 1: 스케줄 실행 - 각각 독립]

Scheduler-1 ──→ ECS UpdateService (nestjs)
Scheduler-2 ──→ ECS UpdateService (python-api)
Scheduler-3 ──→ ECS UpdateService (worker)
     ...
Scheduler-N ──→ ECS UpdateService (service-N)

→ 각 Scheduler는 자기 서비스만 업데이트 (서로 모름)


[경로 2: 알림 수집 - CloudTrail이 중앙에서 수집]

                       ┌──────────────┐
ECS UpdateService ────→│              │←──── ECS UpdateService
ECS UpdateService ────→│  CloudTrail  │←──── ECS UpdateService
ECS UpdateService ────→│  (AWS 자동)   │←──── ECS UpdateService
                       └──────┬───────┘
                              │
                  모든 UpdateService API 호출 기록
                              │
                              ▼
                  ┌───────────────────────┐
                  │    EventBridge Rule   │
                  │  (UpdateService 필터)  │
                  └───────────┬───────────┘
                              │
                              ▼
                  ┌───────────────────────┐
                  │         SQS           │
                  │  (메시지 N개 저장)     │
                  └───────────┬───────────┘
                              │
                              ▼
                  ┌───────────────────────┐
                  │   Lambda (배치 처리)   │
                  │   → Slack 요약 알림    │
                  └───────────────────────┘
```

### 핵심 포인트

| 구성요소 | 역할 |
|---------|------|
| **Scheduler** | 자기 서비스만 업데이트 (서로 독립적) |
| **CloudTrail** | AWS 계정 내 모든 API 호출을 자동으로 중앙 기록 |
| **EventBridge Rule** | CloudTrail에서 `UpdateService` 이벤트만 필터링 |
| **SQS** | 필터링된 이벤트를 쌓아둠 |
| **Lambda** | 모인 메시지를 배치로 처리 → 요약 알림 전송 |

**결론: Scheduler들이 서로 연결되는 게 아니라, CloudTrail이 모든 API 호출을 수집하는 구조**

---

## Q2. SQS가 메시지를 모았다가 Lambda에 어떻게 전달하나요?

### 질문 배경
- SQS에 메시지가 쌓이는 건 이해함
- 그런데 SQS가 어떻게 "모아서" Lambda에 전달하는지?
- Lambda가 어떻게 여러 메시지를 한번에 인지하는지?

### 답변

**핵심: SQS가 아닌 Lambda Event Source Mapping이 배치 처리를 담당**

```
┌─────────────────────────────────────────────────────────────┐
│                        SQS Queue                            │
│  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐       ┌─────┐     │
│  │msg 1│ │msg 2│ │msg 3│ │msg 4│ │msg 5│  ...  │msg N│     │
│  └─────┘ └─────┘ └─────┘ └─────┘ └─────┘       └─────┘     │
└────────────────────────────┬────────────────────────────────┘
                             │
                             │  Lambda Event Source Mapping:
                             │  - batch_size = 10
                             │  - maximum_batching_window = 300초
                             │
                             ▼
              ┌──────────────────────────────┐
              │  AWS가 자동으로 판단:         │
              │  "10개 모였거나 5분 지났나?"   │
              └──────────────┬───────────────┘
                             │
                             │ 조건 충족 시 Lambda 호출
                             ▼
              ┌──────────────────────────────┐
              │         Lambda 함수          │
              │                              │
              │  event['Records'] = [        │
              │    {body: nestjs 정보},      │
              │    {body: python-api 정보},  │
              │    {body: worker 정보},      │
              │    ... (최대 10개)           │
              │  ]                           │
              └──────────────────────────────┘
```

### Terraform 설정

```hcl
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.alerts.arn
  function_name    = aws_lambda_function.slack_notifier.arn

  batch_size                         = 10   # 최대 10개씩 가져옴
  maximum_batching_window_in_seconds = 300  # 최대 5분 대기
}
```

### 트리거 조건

| 조건 | 동작 |
|------|------|
| 메시지 10개 도달 | 즉시 Lambda 호출 |
| 5분 경과 | 현재까지 모인 메시지로 Lambda 호출 |

→ 둘 중 먼저 충족되는 조건으로 트리거

### Lambda가 받는 event 구조

```python
{
    "Records": [
        {
            "messageId": "abc-123",
            "body": "{\"detail\": {\"requestParameters\": {\"service\": \"nestjs\", \"desiredCount\": 1}}}"
        },
        {
            "messageId": "def-456",
            "body": "{\"detail\": {\"requestParameters\": {\"service\": \"python-api\", \"desiredCount\": 1}}}"
        },
        # ... 배치된 메시지들
    ]
}
```

### Lambda 처리 로직

```python
def handler(event, context):
    records = event['Records']  # 여러 메시지가 배열로 전달됨

    results = []
    for record in records:
        body = json.loads(record['body'])
        service_name = body['detail']['requestParameters']['service']
        desired_count = body['detail']['requestParameters']['desiredCount']
        results.append({'service': service_name, 'count': desired_count})

    # 모은 결과를 한번에 Slack으로 전송
    send_summary_to_slack(results)
```

### 핵심 포인트

| 오해 | 실제 |
|------|------|
| SQS가 메시지를 모아서 보냄 | SQS는 단순 저장소 (큐) |
| SQS가 Lambda를 호출함 | Lambda Event Source Mapping이 SQS를 폴링 |
| Lambda가 메시지를 하나씩 받음 | batch_size 설정에 따라 여러 개를 배열로 받음 |

**결론: SQS는 단순 저장소이고, AWS Lambda Event Source Mapping이 배치 처리를 담당**

---

## 관련 문서

- [AWS Lambda - SQS Event Source Mapping](https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html)
- [AWS SQS - Batching](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-batch-api-actions.html)
- [CloudTrail - Event Reference](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-event-reference.html)
