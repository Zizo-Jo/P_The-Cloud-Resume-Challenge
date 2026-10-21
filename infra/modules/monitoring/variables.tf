variable "env" {
  type = string
}

variable "alert_email" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Where alarms are sent. Comes from a GitHub secret, never from the repo. Empty = no subscription (forks, local runs)."
}

variable "lambda_function_name" {
  type = string
}

variable "api_id" {
  type = string
}

variable "uptime_zip" {
  type        = string
  description = "Path to the uptime-check Lambda package built by scripts/build_lambdas.py."
}

variable "site_url" {
  type = string
}

variable "health_url" {
  type = string
}

variable "ops_zip" {
  type        = string
  description = "Path to the ops-publisher Lambda package built by scripts/build_lambdas.py."
}

variable "ops_bucket" {
  type        = string
  description = "Website bucket that holds the /ops status files."
}

variable "budget_name" {
  type = string
}
