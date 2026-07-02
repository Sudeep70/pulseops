variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "bucket_name" {
  type        = string
  description = "Globally unique name for the S3 bucket to hold remote Terraform state"
}

provider "aws" {
  region = var.aws_region
}

# 1. S3 Bucket for Terraform State
resource "aws_s3_bucket" "state" {
  bucket        = var.bucket_name
  force_destroy = true # Set to false in high-security production environments

  tags = {
    Name        = "PulseOps Remote State Store"
    Environment = "Bootstrap"
  }
}

# Enable versioning on state files for recovery history
resource "aws_s3_bucket_versioning" "state_versioning" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Enforce server-side encryption for sensitive variables in state
resource "aws_s3_bucket_server_side_encryption_configuration" "state_encryption" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access to the state bucket
resource "aws_s3_bucket_public_access_block" "state_access" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


# 2. DynamoDB Table for Distributed State Locking
resource "aws_dynamodb_table" "locks" {
  name         = "pulseops-tflocks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name        = "PulseOps Distributed State Locks"
    Environment = "Bootstrap"
  }
}

output "s3_bucket_name" {
  description = "Remote state S3 Bucket name"
  value       = aws_s3_bucket.state.id
}

output "dynamodb_table_name" {
  description = "Distributed locking DynamoDB Table name"
  value       = aws_dynamodb_table.locks.name
}
