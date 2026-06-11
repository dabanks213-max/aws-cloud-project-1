# Troubleshooting Log — AWS Static Website Deployment Pipeline

A record of real problems encountered while building this project, what caused them, and how they were resolved.

---

## 1. CloudFront Returning 403 After Terraform Apply

**Problem:**
After applying Terraform, hitting the CloudFront URL returned an `AccessDenied` XML error.

**Cause:**
The `origin` block in the `aws_cloudfront_distribution` resource was missing the `origin_access_control_id` argument. Without it, CloudFront had no way to authenticate with S3 using OAC.

**Fix:**
Added the OAC reference to the origin block:
```hcl
origin {
  domain_name              = aws_s3_bucket.test-bucket.bucket_regional_domain_name
  origin_id                = "S3-${aws_s3_bucket.test-bucket.id}"
  origin_access_control_id = aws_cloudfront_origin_access_control.my-oac.id
}
```

**Why it works:**
OAC allows CloudFront to sign requests to S3 on your behalf. Without the `origin_access_control_id`, CloudFront sends unsigned requests which S3 rejects because the bucket is private.

---

## 2. Bucket Policy Referencing Wrong Principal

**Problem:**
The S3 bucket policy was using the OAC ARN as the principal, causing authentication to fail.

**Cause:**
OAC does not have its own ARN that goes in the principal field. The correct principal for OAC is the CloudFront service itself, scoped to the specific distribution via a condition.

**Fix:**
Updated the bucket policy to use the CloudFront service principal with a condition:
```json
"Principal": {
    "Service": "cloudfront.amazonaws.com"
},
"Condition": {
    "ArnLike": {
        "AWS:SourceArn": "arn:aws:cloudfront::ACCOUNT_ID:distribution/DISTRIBUTION_ID"
    }
}
```

**Why it works:**
The `cloudfront.amazonaws.com` principal combined with the `ArnLike` condition tells S3 to only accept requests from CloudFront and only from your specific distribution — not from any other CloudFront distribution.

---

## 3. JSON Syntax Error in Bucket Policy Template

**Problem:**
Terraform returned `invalid character '"' after object key:value pair` when applying the bucket policy.

**Cause:**
A missing comma after the `Resource` field in `bucket_policy.tpl`.

**Fix:**
Added the missing comma:
```json
"Resource": "${bucket_arn}/*",
```

**Why it works:**
JSON requires a comma after every key:value pair except the last one in an object. Missing commas are one of the most common JSON formatting errors.

---

## 4. Terraform Variables Not Resolving in Raw JSON String

**Problem:**
Terraform references like `${aws_s3_bucket.test-bucket.arn}` were not resolving when written inside a plain JSON string.

**Cause:**
Raw JSON strings passed directly to the `policy` argument don't support Terraform interpolation.

**Fix:**
Used `templatefile()` to pass dynamic values into the policy:
```hcl
policy = templatefile("${path.module}/bucket_policy.tpl", {
  bucket_arn       = aws_s3_bucket.test-bucket.arn
  distribution_arn = aws_cloudfront_distribution.s3_distribution.arn
})
```

**Why it works:**
`templatefile()` renders the template file and substitutes the variables at apply time, allowing Terraform resource attributes to be injected dynamically into the policy.

---

## 5. index.html Downloading Instead of Rendering

**Problem:**
Hitting the CloudFront URL caused the browser to download `index.html` instead of rendering it as a webpage.

**Cause:**
The file was uploaded to S3 without the correct `Content-Type` metadata. S3 defaulted to `application/octet-stream` which tells browsers to download the file.

**Fix:**
Added `content_type` to the `aws_s3_object` resource:
```hcl
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.test-bucket.id
  key          = "index.html"
  source       = "${path.module}/index.html"
  content_type = "text/html"
}
```

**Why it works:**
Setting `Content-Type` to `text/html` tells the browser the file is an HTML document and should be rendered, not downloaded.

---

## 6. GitHub Actions OIDC Authentication Failing

**Problem:**
GitHub Actions workflow was failing with an access denied error when trying to assume the AWS IAM role.

**Cause:**
The `origin_access_control_id` was missing from the CloudFront origin block (same as issue #1) but more importantly the `permissions` block was missing from the workflow, preventing GitHub from generating an OIDC token.

**Fix:**
Added the `permissions` block to `deploy.yml`:
```yaml
permissions:
  id-token: write
  contents: read
```

**Why it works:**
`id-token: write` is required for GitHub Actions to request an OIDC token from GitHub's token endpoint. Without it, the workflow cannot generate the token needed to authenticate with AWS and assume the IAM role.

---

## 7. CloudFront Serving XML Error Instead of Custom 404 Page

**Problem:**
Hitting a non-existent URL returned an `AccessDenied` XML error instead of the custom `404.html` page.

**Cause:**
Two issues — the `custom_error_response` block only handled 404 errors, but CloudFront returns a 403 (not a 404) when a file doesn't exist in a private S3 bucket. Also the `404.html` file was not being uploaded to S3 via the GitHub Actions sync command initially.

**Fix:**
Added a second `custom_error_response` block for 403 errors:
```hcl
custom_error_response {
  error_code         = 403
  response_code      = 404
  response_page_path = "/404.html"
}

custom_error_response {
  error_code         = 404
  response_code      = 404
  response_page_path = "/404.html"
}
```

**Why it works:**
When S3 can't find a file, it returns a 403 Access Denied (because the bucket is private and the object doesn't exist). CloudFront sees the 403 and maps it to the custom error page, returning a clean 404 response to the user instead of the raw AWS XML error.

---

## 8. Terraform Files Being Synced to S3

**Problem:**
`main.tf`, `output.tf`, `bucket_policy.tpl`, `.gitignore` and `README.md` were all appearing in the S3 bucket alongside the site files.

**Cause:**
The GitHub Actions sync command was syncing the entire repo root directory to S3 without filtering, uploading all files including Terraform infrastructure files.

**Fix:**
Updated the sync command in `deploy.yml` to only include HTML files:
```yaml
aws s3 sync . s3://${{ vars.BUCKET_NAME }} --exclude "*" --include "*.html" --delete
```

**Why it works:**
The `--exclude "*"` flag excludes everything first, then `--include "*.html"` adds back only HTML files. The `--delete` flag removes any files from S3 that no longer exist in the repo, keeping the bucket clean.

---

## 9. CloudFront CreateInvalidation Failing After Terraform Rebuild

**Problem:**
The GitHub Actions workflow failed on the invalidation step with `not authorized to perform: cloudfront:CreateInvalidation` even though it worked before.

**Cause:**
When `terraform destroy` and `terraform apply` are run, CloudFront distributions are recreated with new distribution IDs. The IAM policy was scoped to the old distribution ARN, so it no longer matched. The GitHub variables `DISTRIBUTION_ID` and `STAGING_DISTRIBUTION_ID` were also pointing at the old IDs.

**Fix:**
Two things need to be updated after every `terraform apply` that recreates distributions:

1. Run `terraform output` to get the new distribution IDs and update the GitHub variables `DISTRIBUTION_ID` and `STAGING_DISTRIBUTION_ID` under **Settings → Secrets and variables → Actions → Variables**

2. Make sure the IAM policy references Terraform resource attributes directly rather than hardcoded ARNs so it always stays in sync:
```hcl
Resource = [
  aws_cloudfront_distribution.s3_distribution.arn,
  aws_cloudfront_distribution.staging_distribution.arn
]
```

**Why it works:**
Terraform resolves resource ARNs at apply time, so the policy is always updated with the correct ARNs. The GitHub variables need to be updated manually since they store the distribution ID for the invalidation command.