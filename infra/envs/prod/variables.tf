variable "bucket_name" {
  type        = string
  description = "S3 bucket holding the website files."
}

variable "name_suffix" {
  type        = string
  description = "Suffix in backend resource names (visitors-<suffix>, counter-<suffix>, ...)."
}

variable "alert_email" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Alarm recipient. Set through the ALERT_EMAIL GitHub secret (TF_VAR_alert_email); never committed."
}
