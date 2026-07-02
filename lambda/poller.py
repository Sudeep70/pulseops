import os
import urllib.request
import json
import boto3

def handler(event, context):
    asg_name = os.environ['ASG_NAME']
    region = os.environ.get('AWS_REGION', 'us-east-1')
    
    print(f"Starting health check polling for ASG: {asg_name} in region: {region}")
    
    asg_client = boto3.client('autoscaling', region_name=region)
    ec2_client = boto3.client('ec2', region_name=region)
    cw_client = boto3.client('cloudwatch', region_name=region)
    
    try:
        # 1. Describe the Auto Scaling Group
        response = asg_client.describe_auto_scaling_groups(
            AutoScalingGroupNames=[asg_name]
        )
        asgs = response.get('AutoScalingGroups', [])
        if not asgs:
            print(f"Auto Scaling Group '{asg_name}' not found.")
            return {
                'statusCode': 404,
                'body': f"ASG '{asg_name}' not found."
            }
        
        asg = asgs[0]
        instances = asg.get('Instances', [])
        
        # Only check instances that are InService
        in_service_instances = [
            inst['InstanceId'] for inst in instances 
            if inst['LifecycleState'] == 'InService'
        ]
        
        if not in_service_instances:
            print("No InService instances found in ASG to poll.")
            return {
                'statusCode': 200,
                'body': "No InService instances found."
            }
        
        # 2. Get Public IP addresses of InService instances
        ec2_response = ec2_client.describe_instances(InstanceIds=in_service_instances)
        instance_ips = {}
        for reservation in ec2_response.get('Reservations', []):
            for inst in reservation.get('Instances', []):
                inst_id = inst['InstanceId']
                public_ip = inst.get('PublicIpAddress')
                if public_ip:
                    instance_ips[inst_id] = public_ip
        
        print(f"Found InService instances and public IPs: {instance_ips}")
        
        # 3. Poll /health on each public IP
        for inst_id, public_ip in instance_ips.items():
            health_url = f"http://{public_ip}:5000/health"
            failed = 0
            try:
                req = urllib.request.Request(health_url)
                # 3-second timeout for the health check
                with urllib.request.urlopen(req, timeout=3) as resp:
                    if resp.status == 200:
                        data = json.loads(resp.read().decode('utf-8'))
                        if data.get('status') == 'healthy':
                            print(f"Instance {inst_id} ({public_ip}) is healthy.")
                        else:
                            print(f"Instance {inst_id} ({public_ip}) returned unhealthy status: {data}")
                            failed = 1
                    else:
                        print(f"Instance {inst_id} ({public_ip}) returned status code: {resp.status}")
                        failed = 1
            except Exception as e:
                print(f"Instance {inst_id} ({public_ip}) health check probe failed: {str(e)}")
                failed = 1
            
            # 4. Publish custom metrics to CloudWatch (both per-instance and ASG-aggregate)
            cw_client.put_metric_data(
                Namespace='PulseOps',
                MetricData=[
                    # Per-instance metric for granular history
                    {
                        'MetricName': 'HealthCheckFailed',
                        'Dimensions': [
                            {
                                'Name': 'AutoScalingGroupName',
                                'Value': asg_name
                            },
                            {
                                'Name': 'InstanceId',
                                'Value': inst_id
                            }
                        ],
                        'Value': float(failed),
                        'Unit': 'Count'
                    },
                    # Aggregate metric for the ASG Alarm (allows single Alarm configuration)
                    {
                        'MetricName': 'HealthCheckFailed',
                        'Dimensions': [
                            {
                                'Name': 'AutoScalingGroupName',
                                'Value': asg_name
                            }
                        ],
                        'Value': float(failed),
                        'Unit': 'Count'
                    }
                ]
            )
            print(f"Published custom metrics (failed={failed}) for instance {inst_id}")
            
    except Exception as e:
        print(f"Error in execution of health poller: {str(e)}")
        return {
            'statusCode': 500,
            'body': f"Error: {str(e)}"
        }

    return {
        'statusCode': 200,
        'body': "Polling completed successfully."
    }
