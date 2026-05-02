terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
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

# Dedicated provider for publishing outputs to SSM Parameter Store.
# Defaults to the same region as the deployment but can be redirected
# to a central account or region without touching the main provider.
provider "aws" {
  alias   = "ssm"
  region  = var.ssm_region
  profile = var.ssm_profile

  default_tags {
    tags = local.common_tags
  }
}
