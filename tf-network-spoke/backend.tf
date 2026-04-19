terraform {
  backend "s3" {
    # Update bucket to your Terraform state bucket before running terraform init.
    # Run: terraform init -reconfigure
    bucket       = "REPLACE_WITH_TERRAFORM_STATE_BUCKET"
    key          = "tf-network-spoke/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
