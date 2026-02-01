terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" { region = "us-east-1" }

module "backend" {
  source = "../../modules/backend"
  env    = "dev"
  # 这里指向 src 里的 python 文件
  lambda_source = "${path.module}/../../src/lambda/func.py"
}

module "frontend" {
  source = "../../modules/frontend"
  bucket_name = var.my_bucket_name
  # 这里指向 src 里的 html 文件
  html_source = "${path.module}/../../src/website/index.html"
}