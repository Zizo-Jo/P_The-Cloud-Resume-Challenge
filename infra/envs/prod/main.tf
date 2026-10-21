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

  # Lambda packages come from scripts/build_lambdas.py (run it before plan).
  lambda_zip = "${path.module}/../../../build/counter.zip"
}

module "frontend" {
  source      = "../../modules/frontend"
  bucket_name = var.bucket_name

  html_source               = "${path.module}/../../../src/website/index.html"
  ops_html_source           = "${path.module}/../../../src/website/ops/index.html"
  dir_index_function_source = "${path.module}/../../../src/cloudfront/dir-index.js"
}

module "monitoring" {
  source = "../../modules/monitoring"

  env                  = var.name_suffix
  alert_email          = var.alert_email
  lambda_function_name = module.backend.function_name
  api_id               = module.backend.api_id
  uptime_zip           = "${path.module}/../../../build/uptime.zip"
  site_url             = "https://zihao-cv.site"
  health_url           = module.backend.health_endpoint
  ops_zip              = "${path.module}/../../../build/ops.zip"
  ops_bucket           = var.bucket_name
  budget_name          = "My Zero-Spend Budget"
}
