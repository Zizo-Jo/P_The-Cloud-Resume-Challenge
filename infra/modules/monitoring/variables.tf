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
