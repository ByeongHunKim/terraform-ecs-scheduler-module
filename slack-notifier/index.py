import json
import os
import urllib3
from datetime import datetime

http = urllib3.PoolManager()

def handler(event, context):
    webhook_url = os.environ['SLACK_WEBHOOK_URL']
    
    # Parse SNS Message
    sns_message = json.loads(event['Records'][0]['Sns']['Message'])
    
    detail = sns_message.get('detail', {})
    execution_id = detail.get('executionId', 'UNKNOWN')
    state = detail.get('state', 'UNKNOWN')
    schedule_arn = detail.get('scheduleArn', '')
    
    # Extract schedule name
    schedule_name = schedule_arn.split('/')[-1] if schedule_arn else 'UNKNOWN'
    
    # Determine success/failure
    if state == 'SUCCEEDED':
        color = 'good'
        emoji = ':white_check_mark:'
        title = 'ECS Scheduling Succeeded'
    elif state == 'FAILED':
        color = 'danger'
        emoji = ':x:'
        title = 'ECS Scheduling Failed'
    else:
        color = 'warning'
        emoji = ':question:'
        title = f'ECS Scheduling Status: {state}'
    
    # Slack Message
    message = {
        "attachments": [{
            "color": color,
            "title": f"{emoji} {title}",
            "fields": [
                {
                    "title": "Schedule",
                    "value": schedule_name,
                    "short": True
                },
                {
                    "title": "Status",
                    "value": state,
                    "short": True
                },
                {
                    "title": "Execution ID",
                    "value": execution_id,
                    "short": False
                },
                {
                    "title": "Time",
                    "value": datetime.now().strftime('%Y-%m-%d %H:%M:%S KST'),
                    "short": False
                }
            ],
            "footer": "ECS Scheduler Monitor"
        }]
    }
    
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
