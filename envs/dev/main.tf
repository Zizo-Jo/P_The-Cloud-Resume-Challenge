terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" { region = "us-east-1" }

module "backend" {
  source = "../../modules/backend"
  env    = "dev"
  
  lambda_source = "${path.module}/../../src/lambda/func.py"
}

module "frontend" {
  source = "../../modules/frontend"
  bucket_name = var.my_bucket_name
  
  html_source = "${path.module}/../../src/website/index.html"
}