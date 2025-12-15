````# EventBridge Rule 동작 방식

이 문서는 `aws_cloudwatch_event_rule`이 ECS UpdateService 이벤트를 필터링하는 방식을 설명합니다.

## 1. 전체 아키텍처 흐름

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AWS 내부                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  EventBridge Scheduler                                                      │
│        │                                                                    │
│        ▼ (IAM Role: *-scheduler-role-dev)                                  │
│  ┌───────────┐                                                             │
│  │    ECS    │ UpdateService API 호출                                       │
│  └───────────┘                                                             │
│        │                                                                    │
│        ▼ (자동 기록)                                                         │
│  ┌───────────┐                                                             │
│  │CloudTrail │ 모든 API 호출 기록                                            │
│  └───────────┘                                                             │
│        │                                                                    │
│        ▼ (이벤트 발행)                                                       │
│  ┌───────────────────────────────────────┐                                 │
│  │         EventBridge (Default Bus)      │                                 │
│  │                                        │                                 │
│  │   ┌────────────────────────────────┐  │                                 │
│  │   │  aws_cloudwatch_event_rule     │  │  ← 여기서 필터링!                 │
│  │   │  - source: aws.ecs             │  │                                 │
│  │   │  - eventName: UpdateService    │  │                                 │
│  │   │  - userName suffix 매칭         │  │                                 │
│  │   └────────────────────────────────┘  │                                 │
│  └───────────────────────────────────────┘                                 │
│        │                                                                    │
│        ▼ (매칭된 이벤트만)                                                    │
│  ┌───────────┐                                                             │
│  │    SQS    │ 메시지 배치 (10개 또는 5분)                                    │
│  └───────────┘                                                             │
│        │                                                                    │
│        ▼                                                                    │
│  ┌───────────┐                                                             │
│  │  Lambda   │ 배치 처리 → Slack 전송                                        │
│  └───────────┘                                                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 2. Event Rule의 핵심: event_pattern

```hcl
event_pattern = jsonencode({
  source      = ["aws.ecs"]                           # ① 이벤트 소스
  detail-type = ["AWS API Call via CloudTrail"]       # ② 이벤트 타입
  detail = {
    eventName = ["UpdateService"]                     # ③ API 이름
    userIdentity = {
      sessionContext = {
        sessionIssuer = {
          userName = [{ "suffix": "-scheduler-role-${var.environment}" }]  # ④ 호출자 필터
        }
      }
    }
  }
})
```

### 각 필드 설명

| 필드 | 역할 | 예시 값 |
|------|------|---------|
| `source` | AWS 서비스 식별 | `aws.ecs`, `aws.ec2` 등 |
| `detail-type` | 이벤트 유형 | CloudTrail API 호출 |
| `eventName` | 어떤 API가 호출됐는지 | `UpdateService` |
| `userName` | 누가 호출했는지 (IAM Role 이름) | suffix로 `-scheduler-role-dev` |

## 3. 실제 CloudTrail 이벤트 예시

EventBridge로 들어오는 실제 이벤트:

```json
{
  "source": "aws.ecs",
  "detail-type": "AWS API Call via CloudTrail",
  "detail": {
    "eventName": "UpdateService",
    "userIdentity": {
      "type": "AssumedRole",
      "sessionContext": {
        "sessionIssuer": {
          "type": "Role",
          "userName": "nestjs-scheduler-role-dev"
        }
      }
    },
    "requestParameters": {
      "cluster": "my-cluster",
      "service": "nestjs-service",
      "desiredCount": 1
    }
  }
}
```

> `userName` 필드가 suffix 패턴 `-scheduler-role-dev`와 매칭됩니다.

## 4. 매칭 로직 (AND 조건)

```
source = "aws.ecs"
    AND
detail-type = "AWS API Call via CloudTrail"
    AND
eventName = "UpdateService"
    AND
userName이 "-scheduler-role-dev"로 끝남
```

**모든 조건이 만족해야** Target(SQS)으로 전달됩니다.

## 5. Target 연결

```hcl
resource "aws_cloudwatch_event_target" "send_to_sqs" {
  rule      = aws_cloudwatch_event_rule.ecs_update_service.name
  target_id = "SendToSQS"
  arn       = aws_sqs_queue.alerts.arn  # 매칭된 이벤트 → SQS로 전송
}
```

Rule이 매칭되면 SQS Queue로 이벤트 JSON 전체가 메시지로 들어갑니다.

## 6. 기존 패턴과의 비교

### 기존 패턴 (UpdateService만)

```hcl
event_pattern = {
  source      = ["aws.ecs"]
  detail-type = ["AWS API Call via CloudTrail"]
  detail = {
    eventName = ["UpdateService"]
  }
}
```

**매칭되는 경우:**
- EventBridge Scheduler가 호출한 UpdateService
- AWS 콘솔에서 수동으로 UpdateService
- AWS CLI로 직접 UpdateService
- CI/CD 파이프라인에서 UpdateService

→ **모든 UpdateService 호출**에 대해 Slack 알림 발생

### 새 패턴 (suffix 필터 추가)

**매칭되는 경우:**
- `nestjs-scheduler-role-dev` 같은 스케줄러 IAM Role이 호출한 경우만

**매칭 안 되는 경우:**
- AWS 콘솔에서 수동 조작
- AWS CLI 직접 호출
- CI/CD 파이프라인 (다른 Role 사용)

## 7. 요약

| 단계 | 컴포넌트 | 역할 |
|------|----------|------|
| 1 | CloudTrail | 모든 AWS API 호출 기록 |
| 2 | EventBridge | CloudTrail 이벤트를 실시간 수신 |
| 3 | **Event Rule** | **패턴 매칭으로 필터링** |
| 4 | Event Target | 매칭된 이벤트를 SQS로 라우팅 |
| 5 | SQS | 메시지 배치 |
| 6 | Lambda | 배치 처리 후 Slack 전송 |
````