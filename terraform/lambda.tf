# Archive the Health Poller Lambda script
data "archive_file" "poller_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/poller.py"
  output_path = "${path.module}/../lambda/poller.zip"
}

# Archive the Remediator Lambda script
data "archive_file" "remediator_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/remediator.py"
  output_path = "${path.module}/../lambda/remediator.zip"
}

# 1. Health Poller Lambda Function
resource "aws_lambda_function" "poller" {
  filename         = data.archive_file.poller_zip.output_path
  source_code_hash = data.archive_file.poller_zip.output_base64sha256
  function_name    = "${var.project_name}-health-poller"
  role             = aws_iam_role.poller_role.arn
  handler          = "poller.handler"
  runtime          = "python3.11"
  timeout          = 30

  environment {
    variables = {
      ASG_NAME = aws_autoscaling_group.asg.name
    }
  }

  tags = {
    Name = "${var.project_name}-health-poller-lambda"
  }
}

# Grant CloudWatch EventBridge permission to invoke the Poller Lambda
resource "aws_lambda_permission" "allow_eventbridge_to_poll" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.poller.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_minute.arn
}

# 2. Self-Healing Remediator Lambda Function
resource "aws_lambda_function" "remediator" {
  filename         = data.archive_file.remediator_zip.output_path
  source_code_hash = data.archive_file.remediator_zip.output_base64sha256
  function_name    = "${var.project_name}-remediator"
  role             = aws_iam_role.remediator_role.arn
  handler          = "remediator.handler"
  runtime          = "python3.11"
  timeout          = 30

  environment {
    variables = {
      ASG_NAME = aws_autoscaling_group.asg.name
    }
  }

  tags = {
    Name = "${var.project_name}-remediator-lambda"
  }
}

# Grant SNS permission to invoke the Remediator Lambda
resource "aws_lambda_permission" "allow_sns_to_remediate" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediator.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alarms.arn
}
