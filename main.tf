# This Terraform configuration sets up an S3 bucket, uploads an object, configures the bucket for website hosting, creates a CloudFront distribution with an origin access control, and applies a bucket policy to allow CloudFront to access the S3 bucket.

# Creates an S3 bucket named "my-test-bucket-215616" with a tag for identification.
resource "aws_s3_bucket" "test-bucket" {
  bucket        = "my-test-bucket-215616"
  force_destroy = true

  tags = {
    Name = "my-test-bucket-215616"
  }
}

resource "aws_s3_bucket_versioning" "test-bucket-versioning" {
  bucket = aws_s3_bucket.test-bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Uploads an object (index.html) to the S3 bucket with the specified content type. Make sure to set correct content type for the object.
resource "aws_s3_object" "object" {
  bucket       = aws_s3_bucket.test-bucket.id
  key          = "index.html"
  source       = "C:/Users/Darien/Downloads/index.html"
  content_type = "text/html"
}

resource "aws_s3_object" "error-object" {
  bucket       = aws_s3_bucket.test-bucket.id
  key          = "404.html"
  source       = "${path.module}/404.html"
  content_type = "text/html"
}

# Configures the S3 bucket for website hosting, specifying "index.html" as the index document.
resource "aws_s3_bucket_website_configuration" "bucket-website" {
  bucket = aws_s3_bucket.test-bucket.id
  index_document {
    suffix = "index.html"
  }
}

# Creates a CloudFront origin access control (OAC) to allow CloudFront to access the S3 bucket securely.
resource "aws_cloudfront_origin_access_control" "my-oac" {
  name                              = "my-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Creates a CloudFront distribution that uses the S3 bucket as its origin, with the OAC for secure access. It also sets up caching behavior and geo-restrictions.
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name              = aws_s3_bucket.test-bucket.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.test-bucket.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.my-oac.id
  }

  enabled             = true
  comment             = "S3 distribution for test bucket"
  default_root_object = "index.html"
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.test-bucket.id}"

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
resource "aws_s3_bucket_policy" "bucket-policy" {
  bucket = aws_s3_bucket.test-bucket.id
  policy = templatefile("${path.module}/bucket_policy.tpl", {
    bucket_arn       = aws_s3_bucket.test-bucket.arn
    distribution_arn = aws_cloudfront_distribution.s3_distribution.arn
  })
}

# Creates an IAM policy named "github-actions" that grants permissions to list, delete, and put objects in the S3 bucket, as well as create invalidations in the CloudFront distribution. This policy can be attached to an IAM role used by GitHub Actions for deployment purposes.
resource "aws_iam_policy" "github-actions" {
  name        = "github-actions"
  description = "Policy for Github for s3 project"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:DeleteObject",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.test-bucket.arn,
          "${aws_s3_bucket.test-bucket.arn}/*",
          aws_s3_bucket.test-staging-bucket.arn,
          "${aws_s3_bucket.test-staging-bucket.arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = "cloudfront:CreateInvalidation"
        Resource = [
          aws_cloudfront_distribution.s3_distribution.arn,
          aws_cloudfront_distribution.staging_distribution.arn
        ]
      }
    ]
  })
}

resource "aws_iam_openid_connect_provider" "github-actions-id-provider" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_iam_role" "github-actions-role" {
  name = "github-actions-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github-actions-id-provider.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:dabanks213-max/aws-cloud-project-1:*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github-actions-attach" {
  role       = aws_iam_role.github-actions-role.name
  policy_arn = aws_iam_policy.github-actions.arn
}



