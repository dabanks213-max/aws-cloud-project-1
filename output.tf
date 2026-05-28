output "bucket_name" {
  value = aws_s3_bucket.test-bucket.id
}

output "github_actions_role_arn" {
  value = aws_iam_role.github-actions-role.arn
}

output "distribution_id" {
  value = aws_cloudfront_distribution.s3_distribution.id
}