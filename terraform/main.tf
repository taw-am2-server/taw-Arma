terraform {
  required_version = "~> 0.12.24"
  required_providers {
    aws = ">= 2.59.0"
  }
}

provider "aws" {
  region      = local.primary_region
  profile     = "taw_admin"
  max_retries = 10
}
