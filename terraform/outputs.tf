output "vpc_id" {
  description = "The ID of the custom VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "The list of IDs of public subnets"
  value       = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

output "ecr_repository_url" {
  description = "The registry URL for ECR repository"
  value       = aws_ecr_repository.app.repository_url
}

output "autoscaling_group_name" {
  description = "The name of the Auto Scaling Group"
  value       = aws_autoscaling_group.asg.name
}

output "health_poller_lambda_arn" {
  description = "The ARN of the health poller Lambda"
  value       = aws_lambda_function.poller.arn
}

output "remediator_lambda_arn" {
  description = "The ARN of the remediator/self-healing Lambda"
  value       = aws_lambda_function.remediator.arn
}

output "sns_topic_arn" {
  description = "The ARN of the SNS topic for alarms"
  value       = aws_sns_topic.alarms.arn
}

output "cpu_alarm_name" {
  description = "The name of the High CPU CloudWatch Alarm"
  value       = aws_cloudwatch_metric_alarm.cpu_high.alarm_name
}

output "custom_health_alarm_name" {
  description = "The name of the Custom Health CloudWatch Alarm"
  value       = aws_cloudwatch_metric_alarm.custom_health.alarm_name
}
