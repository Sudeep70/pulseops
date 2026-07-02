terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Replace bucket name with your own unique S3 bucket created via the bootstrap folder
  backend "s3" {
    bucket         = "pulseops-tf-state-815402439541"
    key            = "state/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "pulseops-tflocks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
