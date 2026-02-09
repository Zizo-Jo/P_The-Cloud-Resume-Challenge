resource "aws_s3_bucket" "b" {
  bucket        = var.bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "pub" {
  bucket = aws_s3_bucket.b.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "example-oac"
  description                       = "OAC for S3"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_s3_bucket_policy" "pol" {
  bucket = aws_s3_bucket.b.id
  depends_on = [aws_s3_bucket_public_access_block.pub]
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCloudFrontServicePrincipal"
      Effect = "Allow"
      Principal = {
        Service = "cloudfront.amazonaws.com"
      }
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.b.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.cdn.arn 
        }
      }
    }]
  })
}

resource "aws_s3_object" "html" {
  bucket       = aws_s3_bucket.b.id
  key          = "index.html"
  source       = var.html_source
  content_type = "text/html"
  etag         = filemd5(var.html_source)
}

# ACM Certificate Resource
resource "aws_acm_certificate" "cert" {
  domain_name       = "zihao-cv.site"
  validation_method = "DNS"

  subject_alternative_names = ["www.zihao-cv.site"]

  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront Distribution Resource
resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  default_root_object = "index.html"
  
  aliases = ["zihao-cv.site", "www.zihao-cv.site"]

  origin {
    domain_name = aws_s3_bucket.b.bucket_regional_domain_name
    origin_id   = "S3-Origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-Origin"
    viewer_protocol_policy = "redirect-to-https"
    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
    
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}


