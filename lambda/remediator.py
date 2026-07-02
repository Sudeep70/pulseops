import os
import urllib.request
import json
import boto3

def get_ssm_parameter(name):
    """
    Retrieves the value of a secure or standard parameter from AWS SSM Parameter Store.
    """
    ssm = boto3.client('ssm')
    try:
        response = ssm.get_parameter(Name=name, WithDecryption=True)
        return response['Parameter']['Value']
    except Exception as e:
        print(f"Failed to fetch parameter '{name}': {str(e)}")
        return None

def handler(event, context):
    print("Self-Healing Lambda triggered. Event data:")
    print(json.dumps(event))
    
    asg_name = os.environ['ASG_NAME']
    region = os.environ.get('AWS_REGION', 'us-east-1')
    
    # 1. Parse SNS alert payload
    alarm_name = "Unknown Alarm"
    alarm_description = "No description provided"
    new_state = "ALARM"
    reason = "No details"
    
    try:
        sns_record = event['Records'][0]['Sns']
        sns_message = sns_record['Message']
        print(f"SNS message: {sns_message}")
        
        # Try to parse the SNS message as CloudWatch alarm JSON structure
        try:
            alarm_data = json.loads(sns_message)
            alarm_name = alarm_data.get('AlarmName', alarm_name)
            alarm_description = alarm_data.get('AlarmDescription', alarm_description)
            new_state = alarm_data.get('NewStateValue', new_state)
            reason = alarm_data.get('NewStateReason', reason)
        except json.JSONDecodeError:
            # Fallback for plain text messages
            reason = sns_message[:300]
    except Exception as e:
        print(f"Failed to extract SNS information: {str(e)}")
        reason = "Failed to parse SNS payload."

    action_taken = "No action taken."

    # 2. Remediate: trigger an Instance Refresh if the alarm state is ALARM
    if new_state == "ALARM":
        asg_client = boto3.client('autoscaling', region_name=region)
        try:
            print(f"Triggering instance refresh for Auto Scaling Group: {asg_name}")
            response = asg_client.start_instance_refresh(
                AutoScalingGroupName=asg_name,
                Strategy='Rolling',
                Preferences={
                    'MinHealthyPercentage': 50,
                    'InstanceWarmup': 120
                }
            )
            refresh_id = response.get('InstanceRefreshId')
            action_taken = f"Triggered rolling Instance Refresh on ASG '{asg_name}'. Refresh ID: {refresh_id}"
            print(action_taken)
        except Exception as e:
            action_taken = f"Failed to trigger ASG Instance Refresh: {str(e)}"
            print(action_taken)
    else:
        action_taken = f"Event ignored. State transition was '{new_state}' (not ALARM)."
        print(action_taken)

    # 3. Notify: retrieve Telegram credentials from SSM and send message
    bot_token = get_ssm_parameter('/pulseops/telegram/bot_token')
    chat_id = get_ssm_parameter('/pulseops/telegram/chat_id')

    if bot_token and chat_id:
        # Construct message
        emoji = "🚨" if new_state == "ALARM" else "ℹ️"
        message_text = (
            f"{emoji} *PulseOps Self-Healing Remediation Report* {emoji}\n\n"
            f"*Triggering Alarm:* {alarm_name}\n"
            f"*Description:* {alarm_description}\n"
            f"*Status:* {new_state}\n"
            f"*Incident Reason:* {reason}\n\n"
            f"🛠️ *Action Taken:* {action_taken}"
        )
        
        telegram_url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
        payload = {
            "chat_id": chat_id,
            "text": message_text,
            "parse_mode": "Markdown"
        }
        
        try:
            req = urllib.request.Request(
                telegram_url,
                data=json.dumps(payload).encode('utf-8'),
                headers={'Content-Type': 'application/json'}
            )
            with urllib.request.urlopen(req, timeout=5) as resp:
                print(f"Telegram response status: {resp.status}")
        except Exception as e:
            print(f"Failed to post alert message to Telegram: {str(e)}")
    else:
        print("SSM parameters for Telegram bot credentials not fully populated. Alert message skipped.")

    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Remediation processed.',
            'action': action_taken
        })
    }
