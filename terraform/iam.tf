# ==========================================
# 1. EC2 INSTANCE PROFILE & ROLE
# ==========================================

resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
      }
    ]
  })
}

# Attach policy to pull images from ECR
resource "aws_iam_role_policy_attachment" "ec2_ecr_read" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Attach policy for SSM Session Manager
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}


# ==========================================
# 2. POLLER LAMBDA ROLE & POLICY
# ==========================================

resource "aws_iam_role" "poller_role" {
  name = "${var.project_name}-poller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
      }
    ]
  })
}

# Lambda Basic Execution permissions (for logs)
resource "aws_iam_role_policy_attachment" "poller_basic" {
  role       = aws_iam_role.poller_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for listing resources and putting metrics
resource "aws_iam_policy" "poller_policy" {
  name        = "${var.project_name}-poller-policy"
  description = "Allows Lambda to describe ASG/EC2 and publish custom metrics"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "cloudwatch:PutMetricData"
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "PulseOps"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "poller_custom" {
  role       = aws_iam_role.poller_role.name
  policy_arn = aws_iam_policy.poller_policy.arn
}


# ==========================================
# 3. REMEDIATOR LAMBDA ROLE & POLICY
# ==========================================

resource "aws_iam_role" "remediator_role" {
  name = "${var.project_name}-remediator-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
      }
    ]
  })
}

# Lambda Basic Execution permissions (for logs)
resource "aws_iam_role_policy_attachment" "remediator_basic" {
  role       = aws_iam_role.remediator_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy to trigger instance refresh and fetch SSM parameter store configurations
resource "aws_iam_policy" "remediator_policy" {
  name        = "${var.project_name}-remediator-policy"
  description = "Allows Lambda to trigger ASG Instance Refresh and read SSM parameters"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "autoscaling:StartInstanceRefresh"
        Resource = "*" # Can be scoped to specific ASG ARN if needed
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          "arn:aws:ssm:*:*:parameter/pulseops/telegram/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "remediator_custom" {
  role       = aws_iam_role.remediator_role.name
  policy_arn = aws_iam_policy.remediator_policy.arn
}
