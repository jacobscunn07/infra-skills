terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.43"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = local.common_tags
  }
}

provider "aws" {
  alias   = "ssm"
  region  = var.ssm_region
  profile = var.ssm_profile

  default_tags {
    tags = local.common_tags
  }
}
