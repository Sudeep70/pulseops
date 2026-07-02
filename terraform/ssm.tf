resource "aws_ssm_parameter" "telegram_bot_token" {
  name        = "/pulseops/telegram/bot_token"
  description = "Telegram Bot Token for PulseOps alerting"
  type        = "SecureString"
  value       = var.telegram_bot_token
  tier        = "Standard"

  lifecycle {
    ignore_changes = [value] # Allow manual updates directly in AWS console or CLI without TF overwriting
  }
}

resource "aws_ssm_parameter" "telegram_chat_id" {
  name        = "/pulseops/telegram/chat_id"
  description = "Telegram Chat ID for PulseOps alerting"
  type        = "String"
  value       = var.telegram_chat_id
  tier        = "Standard"

  lifecycle {
    ignore_changes = [value] # Allow manual updates directly in AWS console or CLI without TF overwriting
  }
}
