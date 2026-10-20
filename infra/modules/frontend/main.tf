resource "aws_s3_bucket" "b" {
  bucket = var.bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "pub" {
  bucket                  = aws_s3_bucket.b.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Keep every version of index.html so a bad deploy can be rolled back, and
# let old versions expire so they do not accumulate cost.
resource "aws_s3_bucket_versioning" "v" {
  bucket = aws_s3_bucket.b.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "lc" {
  bucket     = aws_s3_bucket.b.id
  depends_on = [aws_s3_bucket_versioning.v]

  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "zihao-resume-oac"
  description                       = "OAC for S3"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_s3_bucket_policy" "pol" {
  bucket     = aws_s3_bucket.b.id
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

# Browser-side protections sent with every response.
resource "aws_cloudfront_response_headers_policy" "security" {
  name = "security-headers"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 31536000 # 1 year: always use HTTPS
      include_subdomains         = true
      preload                    = true
      override                   = true
    }
    content_type_options {
      override = true # nosniff
    }
    frame_options {
      frame_option = "DENY" # nobody may embed the site in a frame
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
  }
}

# AWS-managed cache policy: gzip/brotli, 1 day default TTL, no cookies or query strings.
data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

# CloudFront Distribution Resource
resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  default_root_object = "index.html"

  aliases = ["zihao-cv.site", "www.zihao-cv.site"]

  origin {
    domain_name              = aws_s3_bucket.b.bucket_regional_domain_name
    origin_id                = "S3-Origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = "S3-Origin"
    viewer_protocol_policy     = "redirect-to-https"
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.optimized.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id
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


