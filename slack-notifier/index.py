import json
import os
import urllib3
from datetime import datetime, timedelta

http = urllib3.PoolManager()

def handler(event, context):
    webhook_url = os.environ['SLACK_WEBHOOK_URL']

    # Parse SNS Message
    sns_message = json.loads(event['Records'][0]['Sns']['Message'])

    detail = sns_message.get('detail', {})

    # Extract information from CloudTrail event
    event_name = detail.get('eventName', 'UNKNOWN')
    request_params = detail.get('requestParameters', {})
    response_elements = detail.get('responseElements', {})
    user_identity = detail.get('userIdentity', {})

    # Service information
    service_name = request_params.get('service', 'UNKNOWN')
    cluster_name = request_params.get('cluster', 'UNKNOWN')
    desired_count = request_params.get('desiredCount', 'UNKNOWN')

    # Executor information
    session_context = user_identity.get('sessionContext', {})
    session_issuer = session_context.get('sessionIssuer', {})
    role_name = session_issuer.get('userName', 'UNKNOWN')

    # Determine success/failure (success if no errorCode)
    error_code = detail.get('errorCode')
    error_message = detail.get('errorMessage', '')

    if error_code:
        color = 'danger'
        emoji = ':x:'
        title = 'ECS Scheduling Failed'
        status = f'FAILED: {error_code}'
    else:
        color = 'good'
        emoji = ':white_check_mark:'
        title = 'ECS Scheduling Succeeded'
        status = 'SUCCEEDED'

    # Determine action (Scale Up/Down)
    if desired_count == 0:
        action = 'Scale Down'
    elif desired_count >= 1:
        action = 'Scale Up'
    else:
        action = 'Update'

    # Convert UTC to KST (+9 hours)
    kst_time = datetime.utcnow() + timedelta(hours=9)
    formatted_time = kst_time.strftime('%Y-%m-%d %H:%M:%S KST')

    # Slack Message
    message = {
        "attachments": [{
            "color": color,
            "title": f"{emoji} {title}",
            "fields": [
                {
                    "title": "Service",
                    "value": service_name,
                    "short": True
                },
                {
                    "title": "Action",
                    "value": f"{action} (→ {desired_count})",
                    "short": True
                },
                {
                    "title": "Cluster",
                    "value": cluster_name,
                    "short": True
                },
                {
                    "title": "Status",
                    "value": status,
                    "short": True
                },
                {
                    "title": "Scheduler Role",
                    "value": role_name,
                    "short": False
                },
                {
                    "title": "Time",
                    "value": formatted_time,
                    "short": False
                }
            ],
            "footer": "ECS Scheduler Monitor"
        }]
    }

    # Add error message if failed
    if error_code:
        message["attachments"][0]["fields"].append({
            "title": "Error",
            "value": error_message[:200],  # Limit to 200 characters
            "short": False
        })

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