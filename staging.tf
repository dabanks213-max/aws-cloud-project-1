# This Terraform configuration sets up an S3 bucket, uploads an object, configures the bucket for website hosting, creates a CloudFront distribution with an origin access control, and applies a bucket policy to allow CloudFront to access the S3 bucket.

# Creates an S3 bucket named "my-test-staging-bucket-215616" with a tag for identification.
resource "aws_s3_bucket" "test-staging-bucket" {
  bucket        = "my-test-staging-bucket-215616"
  force_destroy = true

  tags = {
    Name = "my-test-staging-bucket-215616"
  }
}

resource "aws_s3_bucket_versioning" "staging-bucket-versioning" {
  bucket = aws_s3_bucket.test-staging-bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Uploads an object (index.html) to the S3 bucket with the specified content type. Make sure to set correct content type for the object.
resource "aws_s3_object" "staging-object" {
  bucket       = aws_s3_bucket.test-staging-bucket.id
  key          = "index.html"
  source       = "${path.module}/index.html"
  content_type = "text/html"
}

resource "aws_s3_object" "staging-error-object" {
  bucket       = aws_s3_bucket.test-staging-bucket.id
  key          = "404.html"
  source       = "${path.module}/404.html"
  content_type = "text/html"
}


# Creates a CloudFront origin access control (OAC) to allow CloudFront to access the S3 bucket securely.
resource "aws_cloudfront_origin_access_control" "staging-oac" {
  name                              = "staging-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Creates a CloudFront distribution that uses the S3 bucket as its origin, with the OAC for secure access. It also sets up caching behavior and geo-restrictions.
resource "aws_cloudfront_distribution" "staging_distribution" {
  origin {
    domain_name              = aws_s3_bucket.test-staging-bucket.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.test-staging-bucket.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.staging-oac.id
  }

  enabled             = true
  comment             = "S3 distribution for test bucket"
  default_root_object = "index.html"
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.test-staging-bucket.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 404
    response_page_path = "/404.html"
  }

  custom_error_response {
    error_code         = 403
    response_code      = 404
    response_page_path = "/404.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US"]
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# Applies a bucket policy to the S3 bucket that allows CloudFront to access the objects in the bucket. The policy is generated using a template file (bucket_policy.tpl) that includes the necessary permissions and conditions for secure access.
resource "aws_s3_bucket_policy" "staging-bucket-policy" {
  bucket = aws_s3_bucket.test-staging-bucket.id
  policy = templatefile("${path.module}/bucket_policy.tpl", {
    bucket_arn       = aws_s3_bucket.test-staging-bucket.arn
    distribution_arn = aws_cloudfront_distribution.staging_distribution.arn
  })
}






