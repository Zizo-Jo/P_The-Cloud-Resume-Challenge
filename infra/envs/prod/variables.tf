variable "bucket_name" {
  type        = string
  description = "S3 bucket holding the website files."
}

variable "name_suffix" {
  type        = string
  description = "Suffix in backend resource names (visitors-<suffix>, counter-<suffix>, ...)."
}
