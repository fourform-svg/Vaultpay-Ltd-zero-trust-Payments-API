terraform {
  required_version = ">= 1.5.0"
  required_providers { aws = { source = "hashicorp/aws" version = "~> 5.0" } }
  backend "s3" {
    bucket = "vaultpay-terraform-state-eu-west-2"
    key = "vaultpay-api/terraform.tfstate"
    region = "eu-west-2"
    dynamodb_table = "terraform-locks"
    encrypt = true
  }
}
provider "aws" { region = var.region }
