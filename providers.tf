provider "aws" {
  alias  = "virginia"
  region = "us-east-1"
}

terraform {
  required_version = ">= 0.13.5, <= 0.14.10"

  required_providers {
    aws = "3.35.0" # Exact version to make sure we don't get undesired updates
  }
}
