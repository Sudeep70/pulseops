# Fetch the latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = data.aws_ami.amazon_linux_2023.id
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2_profile.arn
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ec2_sg.id]
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    # Update packages
    dnf update -y
    
    # Install and configure Docker
    dnf install -y docker
    systemctl start docker
    systemctl enable docker
    usermod -aG docker ec2-user
    
    # Authenticate to ECR and pull image
    # Note: ECR login password is fetched using instance IAM role credentials
    aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.app.repository_url}
    
    # Pull and run the Flask application container
    docker pull ${aws_ecr_repository.app.repository_url}:latest
    docker run -d \
      --name pulseops-container \
      --restart always \
      -p 5000:5000 \
      ${aws_ecr_repository.app.repository_url}:latest
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-asg-instance"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "asg" {
  name_prefix         = "${var.project_name}-asg-"
  vpc_zone_identifier = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  min_size         = 1
  max_size         = 3
  desired_capacity = 2

  health_check_type         = "EC2"
  health_check_grace_period = 300 # 5 minutes grace period for boot + docker download

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  # Allow instance refresh to roll updates when Launch Template changes
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 120
    }
  }

  lifecycle {
    create_before_destroy = true
    # Ignore changes to desired capacity to prevent TF overwriting ASG scaling adjustments
    ignore_changes = [desired_capacity]
  }
}

# Target Tracking Auto Scaling Policy based on Average CPU Utilization
resource "aws_autoscaling_policy" "cpu_scaling" {
  name                   = "${var.project_name}-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.asg.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50.0
  }
}
