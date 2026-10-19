# Outputs for DNS Validation and CloudFront URL

output "cloudfront_url" {
  value = aws_cloudfront_distribution.cdn.domain_name
}

output "acm_certificate_cname" {
  value = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
}