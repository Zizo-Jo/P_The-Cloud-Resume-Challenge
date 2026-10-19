output "API_URL" { value = module.backend.api_endpoint }
output "WEBSITE_URL" { value = module.frontend.cloudfront_url }
output "CLOUDFRONT_DISTRIBUTION_ID" { value = module.frontend.cloudfront_distribution_id }
