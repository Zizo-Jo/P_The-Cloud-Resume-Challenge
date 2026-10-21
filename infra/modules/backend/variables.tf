variable "env" { type = string }
variable "lambda_zip" {
  type        = string
  description = "Path to the counter Lambda package built by scripts/build_lambdas.py."
}