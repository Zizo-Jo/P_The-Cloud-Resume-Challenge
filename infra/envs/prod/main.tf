terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }

  backend "s3" {
    bucket       = "zihao-tfstate-030342421998"
    key          = "prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" { region = "us-east-1" }

module "backend" {
  source = "../../modules/backend"
  env    = var.name_suffix

  lambda_source = "${path.module}/../../../src/lambda/func.py"
}

module "frontend" {
  source      = "../../modules/frontend"
  bucket_name = var.bucket_name

  html_source = "${path.module}/../../../src/website/index.html"
}
