# 1. EventBridge Rule: Trigger health check poller every minute
resource "aws_cloudwatch_event_rule" "every_minute" {
  name                = "${var.project_name}-poll-every-minute"
  description         = "Triggers PulseOps health poller Lambda every 1 minute"
  schedule_expression = "rate(1 minute)"

  tags = {
    Name = "${var.project_name}-every-minute-rule"
  }
}

resource "aws_cloudwatch_event_target" "poll_target" {
  rule      = aws_cloudwatch_event_rule.every_minute.name
  target_id = "TriggerPollerLambda"
  arn       = aws_lambda_function.poller.arn
}


# 2. SNS Alert Topic
resource "aws_sns_topic" "alarms" {
  name = "${var.project_name}-alarms"

  tags = {
    Name = "${var.project_name}-sns-topic"
  }
}

# SNS Subscription to trigger the Remediator Lambda
resource "aws_sns_topic_subscription" "remediator_sub" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.remediator.arn
}


# 3. CloudWatch Alarm: ASG Average CPU Utilization >= 70%
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-asg-high-cpu"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "This alarm triggers when the Auto Scaling Group average CPU utilization exceeds 70%."
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.asg.name
  }

  tags = {
    Name = "${var.project_name}-high-cpu-alarm"
  }
}


# 4. CloudWatch Alarm: Custom Health Check Failures >= 1
resource "aws_cloudwatch_metric_alarm" "custom_health" {
  alarm_name          = "${var.project_name}-custom-health-failed"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthCheckFailed"
  namespace           = "PulseOps"
  period              = 60
  statistic           = "Maximum" # Takes the highest value (1) if any instance failed during the minute
  threshold           = 1
  alarm_description   = "This alarm triggers when the custom health check poller reports any instance failure (value >= 1)."
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.asg.name
  }

  tags = {
    Name = "${var.project_name}-custom-health-alarm"
  }
}
