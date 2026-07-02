# PulseOps: Self-Healing AWS CI/CD Pipeline (Free-Tier Optimized)

PulseOps is a production-grade demonstration of Infrastructure-as-Code (IaC), GitOps, cloud monitoring, and automated self-healing workflows, designed to run **strictly within the AWS Free Tier**. 

By removing costly resources like Application Load Balancers (ALBs) and NAT Gateways, this architecture achieves zero-cost idle operation while still providing multi-AZ scaling, automated application health polling, and event-driven remediation.

---

## Architecture Diagram

```mermaid
graph TD
    subgraph GitHub
        GHA[GitHub Actions CI/CD]
    end

    subgraph AWS Cloud
        subgraph VPC [VPC: 10.0.0.0/16]
            IGW[Internet Gateway]
            
            subgraph Public Subnets [Public Subnets - 2 AZs]
                ASG[Auto Scaling Group]
                EC2_1[EC2 Instance 1 (Public IP)]
                EC2_2[EC2 Instance 2 (Public IP)]
            end
        end

        subgraph Container Services
            ECR[Amazon Elastic Container Registry]
        end

        subgraph Management & Monitoring
            EB_Rule[EventBridge Rule: Every 1 Min]
            Poller_Lambda[Health Poller Lambda]
            CW_Custom_Metric[Custom Metric: HealthCheckFailed]
            
            CW_Alarm_CPU[CloudWatch Alarm: High CPU]
            CW_Alarm_Custom[CloudWatch Alarm: HealthCheckFailed >= 1]
            
            SNS[SNS Topic: pulseops-alerts]
            Remediator_Lambda[Self-Healing Lambda]
            S3_TF[S3 Remote State + DynamoDB Lock]
        end
    end

    subgraph External
        Telegram[Telegram Bot API]
    end

    GHA -->|1. Build & Push Image| ECR
    GHA -->|2. Deploy Infrastructure| S3_TF
    GHA -->|3. Trigger Instance Refresh| ASG
    
    EC2_1 & EC2_2 -->|Pull image| ECR
    
    EB_Rule -->|Trigger| Poller_Lambda
    Poller_Lambda -->|1. Query Public IP & HTTP /health| EC2_1
    Poller_Lambda -->|2. Query Public IP & HTTP /health| EC2_2
    Poller_Lambda -->|3. Publish| CW_Custom_Metric
    
    CW_Custom_Metric -->|Metrics| CW_Alarm_Custom
    ASG -->|Metrics| CW_Alarm_CPU
    
    CW_Alarm_CPU -->|Trigger| SNS
    CW_Alarm_Custom -->|Trigger| SNS
    SNS -->|Trigger| Remediator_Lambda
    
    Remediator_Lambda -->|1. start-instance-refresh| ASG
    Remediator_Lambda -->|2. Send alert| Telegram
```

---

## Free-Tier Design Decisions & Tradeoffs

This project is engineered to work 100% within the **AWS Free Tier (12-Month Free and Always-Free)** limits:
- **No NAT Gateway**: Private EC2 instances require a NAT Gateway to fetch Docker Hub/ECR images, which costs ~$32/month. Instead, we place the ASG instances in **Public Subnets** and auto-assign public IPs. They download the images directly via the Internet Gateway (free).
- **No ALB**: Application Load Balancers cost ~$16/month. To bypass this, we expose the Flask application port `5000` directly. Users and checking services connect to the instances' public IPs.
- **Custom Health Poller**: Since there is no ALB to execute health checks, we deploy an **EventBridge Scheduled Lambda** that runs once per minute to poll each instance's `/health` endpoint and emit a custom CloudWatch metric `HealthCheckFailed`. This stays well within the 1,000,000 free Lambda requests/month.
- **SSM Parameter Store**: We enforce **Standard Tier** parameter types which are 100% free (Advanced parameter tiers carry charges).
- **ECR Lifecycle Rules**: ECR storage is limited to 500MB free per month. We deploy a lifecycle policy that automatically deletes untagged/old builds, retaining only the latest 3 builds to ensure we stay under the storage limit.

### Security Tradeoffs
1. **Public IPs and Port 5000 Exposure**: Port `5000` is open to `0.0.0.0/0` on the EC2 security group since there is no ALB to restrict inbound traffic to a load balancer. This is a deliberate tradeoff to fit the project within the AWS Free Tier for a short-lived demonstration, and is not intended for long-running production use.
2. **No SSH (Port 22)**: Management port 22 is completely closed. Instead, administration is handled via **AWS Systems Manager (SSM) Session Manager** (which is secure, encrypted, logged, and entirely free).

---

## File Structure

```text
/pulseops
├── .github/
│   └── workflows/
│       └── pipeline.yml       # GHA Workflow (PR Verify, Main Deploy + Refresh)
├── app/
│   ├── app.py                 # Minimal Flask application with IMDSv2 lookup
│   ├── Dockerfile             # Docker packaging configuration
│   └── requirements.txt       # Python dependencies
├── lambda/
│   ├── poller.py              # Probes instances, writes custom CloudWatch metrics
│   └── remediator.py          # Triggers ASG Instance Refresh, alerts Telegram
└── terraform/
    ├── bootstrap/
    │   └── main.tf            # Bootstrap S3 state bucket + DynamoDB locks
    ├── asg.tf                 # EC2 Autoscaling, Launch Template & user-data
    ├── ecr.tf                 # ECR registry & lifecycle limits
    ├── iam.tf                 # Least-privilege IAM Roles & instance profiles
    ├── lambda.tf              # Lambda zip-packaging & deployment
    ├── monitoring.tf          # CloudWatch alarms, EventBridge trigger, SNS alerts
    ├── outputs.tf             # Terraform terminal output values
    ├── provider.tf            # Provider versioning & backend configuration
    ├── security_groups.tf     # Least-privilege inbound/outbound rules
    ├── ssm.tf                 # Standard-tier parameter storage
    ├── variables.tf           # Configuration inputs
    └── vpc.tf                 # VPC definition (IGW + Public Subnets only)
```

---

## Setup & Deployment Guide

### Prerequisites
1. An AWS Account.
2. The AWS CLI installed and configured locally.
3. Terraform v1.5.0+ installed locally.
4. A Telegram Bot token (create one via `@BotFather`) and your Chat ID (retrieve via `@userinfobot`).

### Step 1: Bootstrap Terraform State Backend
Before running the main infrastructure, we need to create the S3 bucket and DynamoDB table where the state files will be securely stored.

1. Navigate to `/terraform/bootstrap`:
   ```bash
   cd terraform/bootstrap
   ```
2. Initialize and apply:
   ```bash
   terraform init
   terraform apply -var="bucket_name=pulseops-tfstate-<YOUR_AWS_ACCOUNT_ID>"
   ```
3. Record the bucket name. Navigate back:
   ```bash
   cd ..
   ```
4. Open [provider.tf](file:///e:/codes/pulseops/terraform/provider.tf) and replace the backend `bucket` name with the newly created bucket name.

### Step 2: Configure Github Repository Secrets
In your Github Repository, navigate to **Settings > Secrets and Variables > Actions** and create the following Repository Secrets:
- `AWS_ACCESS_KEY_ID`: Your AWS access key.
- `AWS_SECRET_ACCESS_KEY`: Your AWS secret access key.
- `AWS_REGION`: e.g., `us-east-1`

### Step 3: Configure GitHub Environment Gate
1. In your Github Repository, navigate to **Settings > Environments**.
2. Click **New Environment** and name it `production`.
3. Check **Required reviewers** and add yourself. This creates the manual approval gate before running `terraform apply`.

### Step 4: Add Telegram Credentials
To deploy successfully without exposing secrets, you can either:
- Supply them during local deployment:
  Add variables to your `terraform.tfvars` file:
  ```hcl
  telegram_bot_token = "123456789:ABCdefGhIJKlmNoPQRsTUVwxyZ"
  telegram_chat_id   = "987654321"
  ```
- Or write them directly into AWS SSM Parameter Store manually (they are set to be ignored in subsequent Terraform runs):
  - `/pulseops/telegram/bot_token` (SecureString)
  - `/pulseops/telegram/chat_id` (String)

### Step 5: Initial Deploy
To perform the initial deploy (which builds infrastructure and creates the ECR repository):
1. Initialize the main directory:
   ```bash
   cd terraform
   terraform init
   terraform apply -var="telegram_bot_token=YOUR_TOKEN" -var="telegram_chat_id=YOUR_CHAT_ID"
   ```
2. Once applied, Terraform outputs will show the ECR repository URL.

### Step 6: Initial App Push
To build the initial Docker image and push it to ECR (which the EC2 instances will pull on boot):
1. Authenticate to ECR:
   ```bash
   aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <ECR_REPOSITORY_URL>
   ```
2. Build and push:
   ```bash
   cd ../app
   docker build -t pulseops-app .
   docker tag pulseops-app:latest <ECR_REPOSITORY_URL>:latest
   docker push <ECR_REPOSITORY_URL>:latest
   ```
3. Trigger a manual instance refresh to pull this initial image:
   ```bash
   aws autoscaling start-instance-refresh --auto-scaling-group-name <ASG_NAME>
   ```

Now, any subsequent commit to `main` will run validation, wait for approval, build/push the image, and trigger a rolling ASG refresh automatically!

---

## The Chaos Testing Playbook

To prove that the self-healing and autoscaling mechanisms work, perform these tests:

### Chaos Test 1: Manual Instance Termination (EC2 Autoscaling)
This tests standard EC2-level health checks.

1. Go to the AWS EC2 Console, select one of the two active EC2 instances starting with `pulseops-asg-instance`, and click **Terminate Instance**.
2. Observe the ASG health check state. Within 1–2 minutes, the ASG will detect that the instance count has dropped below the desired capacity of `2`.
3. A new instance will be provisioned automatically, run the user data script, pull the Docker container, and enter `InService` status.

### Chaos Test 2: Simulating Application Failure (Self-Healing & Alerts)
This tests application-level self-healing (Flask container stops responding, but the EC2 instance remains online).

1. Connect to one of the EC2 instances via **SSM Session Manager** (no SSH keys needed):
   ```bash
   aws ssm start-session --target <INSTANCE_ID>
   ```
2. Kill the running Docker container to simulate application crash:
   ```bash
   sudo docker stop pulseops-container
   ```
3. **Observe the self-healing workflow**:
   - Within 60 seconds, the Scheduled **Health Poller Lambda** will execute. It makes an HTTP request to `http://<Instance_Public_IP>:5000/health`, which will fail.
   - The Poller Lambda publishes custom metric `HealthCheckFailed = 1` for this instance and the ASG.
   - The CloudWatch Alarm `pulseops-custom-health-failed` detects `HealthCheckFailed >= 1` and enters the `ALARM` state.
   - The Alarm publishes a message to the SNS topic `pulseops-alarms`.
   - The **Remediator Lambda** is invoked by SNS. It triggers a rolling **Instance Refresh** on the Auto Scaling Group.
   - The Remediator Lambda fetches your Telegram credentials from the SSM Parameter Store and posts a message:
     ```text
     🚨 PulseOps Self-Healing Remediation Report 🚨
     
     Triggering Alarm: pulseops-custom-health-failed
     Status: ALARM
     Incident Reason: Threshold breached: HealthCheckFailed >= 1.0
     
     🛠️ Action Taken: Triggered rolling Instance Refresh on ASG 'pulseops-asg-xxxx'. Refresh ID: xxxx-xxxx
     ```
   - The ASG terminates the unhealthy instance and launches a fresh one to restore service.
