import json
import os
import urllib3
from datetime import datetime, timedelta

http = urllib3.PoolManager()


def handler(event, context):
    webhook_url = os.environ['SLACK_WEBHOOK_URL']
    environment = os.environ.get('ENVIRONMENT', 'unknown')

    # Process all SQS records (batch)
    records = event.get('Records', [])
    results = []

    for record in records:
        try:
            # SQS message body contains the EventBridge event
            body = json.loads(record['body'])
            detail = body.get('detail', {})

            # Extract information from CloudTrail event
            request_params = detail.get('requestParameters', {})
            user_identity = detail.get('userIdentity', {})

            # Service information
            service_name = request_params.get('service', 'UNKNOWN')
            cluster_name = request_params.get('cluster', 'UNKNOWN')
            desired_count = request_params.get('desiredCount', 'UNKNOWN')

            # Executor information
            session_context = user_identity.get('sessionContext', {})
            session_issuer = session_context.get('sessionIssuer', {})
            role_name = session_issuer.get('userName', 'UNKNOWN')

            # Determine success/failure
            error_code = detail.get('errorCode')
            error_message = detail.get('errorMessage', '')

            # Determine action (Scale Up/Down)
            if desired_count == 0:
                action = 'Scale Down'
            elif isinstance(desired_count, int) and desired_count >= 1:
                action = 'Scale Up'
            else:
                action = 'Update'

            results.append({
                'service': service_name,
                'cluster': cluster_name,
                'action': action,
                'desired_count': desired_count,
                'role': role_name,
                'success': error_code is None,
                'error_code': error_code,
                'error_message': error_message
            })
        except Exception as e:
            print(f"Error parsing record: {e}")
            continue

    if not results:
        print("No valid records to process")
        return {'statusCode': 200}

    # Build summary message
    message = build_summary_message(results, environment)

    # Send to Slack
    try:
        response = http.request(
            'POST',
            webhook_url,
            body=json.dumps(message).encode('utf-8'),
            headers={'Content-Type': 'application/json'}
        )
        print(f"Slack notification sent: {response.status}")
    except Exception as e:
        print(f"Error sending Slack notification: {e}")

    return {'statusCode': 200}


def build_summary_message(results, environment):
    """Build a summary Slack message from batch results"""

    # Convert UTC to KST (+9 hours)
    kst_time = datetime.utcnow() + timedelta(hours=9)
    formatted_time = kst_time.strftime('%Y-%m-%d %H:%M:%S KST')

    # Count successes and failures
    successes = [r for r in results if r['success']]
    failures = [r for r in results if not r['success']]

    # Determine overall color
    if len(failures) == 0:
        color = 'good'
        emoji = ':white_check_mark:'
        title = 'ECS Scheduled Scaling Completed'
    elif len(successes) == 0:
        color = 'danger'
        emoji = ':x:'
        title = 'ECS Scheduled Scaling Failed'
    else:
        color = 'warning'
        emoji = ':warning:'
        title = 'ECS Scheduled Scaling Partially Completed'

    # Build service list
    service_lines = []
    for r in results:
        status_icon = ':white_check_mark:' if r['success'] else ':x:'
        service_lines.append(
            f"{status_icon} `{r['service']}` - {r['action']} (-> {r['desired_count']})"
        )

    service_list = '\n'.join(service_lines)

    # Build fields
    fields = [
        {
            "title": "Environment",
            "value": environment.upper(),
            "short": True
        },
        {
            "title": "Total Services",
            "value": f"{len(results)} ({len(successes)} succeeded, {len(failures)} failed)",
            "short": True
        },
        {
            "title": "Services",
            "value": service_list,
            "short": False
        },
        {
            "title": "Time",
            "value": formatted_time,
            "short": False
        }
    ]

    # Add failure details if any
    if failures:
        failure_details = []
        for f in failures:
            failure_details.append(
                f"- `{f['service']}`: {f['error_code']} - {f['error_message'][:100]}"
            )
        fields.append({
            "title": ":x: Failure Details",
            "value": '\n'.join(failure_details),
            "short": False
        })

    message = {
        "attachments": [{
            "color": color,
            "title": f"{emoji} {title}",
            "fields": fields,
            "footer": "ECS Scheduler Monitor"
        }]
    }

    return message
