terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "3.1.0"
    }
  }
}

provider "aws" {
  default_tags {
    tags = {
      Project     = "coalfire"
      Environment = "poc"
      ManagedBy   = "Terraform"
    }
  }
}
