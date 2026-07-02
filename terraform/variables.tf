variable "aws_region" {
  type        = string
  description = "The target AWS Region for deployment"
  default     = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "Prefix name for all resources in this pipeline"
  default     = "pulseops"
}

variable "environment" {
  type        = string
  description = "Deployment environment name"
  default     = "production"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance size for ASG (Free-Tier eligible)"
  default     = "t3.micro"
}

variable "telegram_bot_token" {
  type        = string
  description = "The Telegram Bot Token for sending alert reports (SecureString)"
  default     = "PLACEHOLDER_TOKEN"
  sensitive   = true
}

variable "telegram_chat_id" {
  type        = string
  description = "The Telegram chat ID to receive alerts (String)"
  default     = "PLACEHOLDER_CHAT_ID"
}
