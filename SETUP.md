# Setup Guide

This guide walks you through building this project from scratch. By the end you will have a fully automated CI/CD pipeline deploying a static website to AWS with separate production and staging environments.

**Estimated time:** 2-4 hours

---

## Prerequisites

Before you start make sure you have the following installed and configured:

- [Terraform](https://developer.hashicorp.com/terraform/install) — Infrastructure as Code tool
- [AWS CLI](https://aws.amazon.com/cli/) — run `aws configure` to set up your credentials
- [Git](https://git-scm.com/) — version control
- An AWS account with admin access
- A GitHub account with a new empty repository

---

## Phase 1 — Manual AWS Setup

The goal of this phase is to build the infrastructure manually first so you understand how the pieces connect before automating everything in Phase 2.

### Step 1 — Create a private S3 bucket

1. Go to **S3** in the AWS console and click **Create bucket**
2. Give it a unique name (e.g. `my-site-bucket-123456`)
3. Leave **Block all public access** enabled — this is important
4. Enable **Bucket versioning**
5. Click **Create bucket**

### Step 2 — Create a CloudFront Origin Access Control

1. Go to **CloudFront → Origin access**
2. Click **Create control setting**
3. Give it a name, set origin type to **S3**, signing behavior to **Always**
4. Click **Create**

### Step 3 — Create a CloudFront distribution

1. Go to **CloudFront → Distributions → Create distribution**
2. For **Origin domain** select your S3 bucket from the dropdown (not the website endpoint URL)
3. Under **Origin access** select your OAC
4. Set **Default root object** to `index.html`
5. Under **Viewer protocol policy** select **Redirect HTTP to HTTPS**
6. Click **Create distribution**

After creating the distribution AWS will prompt you to copy an updated bucket policy — copy it and apply it to your S3 bucket under **Permissions → Bucket policy**.

### Step 4 — Test

Upload a simple `index.html` to your S3 bucket and hit the CloudFront URL. It should load over HTTPS.

---

## Phase 2 — Infrastructure as Code with Terraform

The goal is to recreate everything from Phase 1 in Terraform so your infrastructure is repeatable and version controlled.

### Step 1 — Initialize Terraform

Create a `main.tf` file and add the AWS provider:

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
```

Run `terraform init` to download the provider.

### Step 2 — Define your S3 bucket

```hcl
resource "aws_s3_bucket" "my-bucket" {
  bucket        = "my-site-bucket-123456"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "my-bucket-versioning" {
  bucket = aws_s3_bucket.my-bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}
```

### Step 3 — Define your OAC and CloudFront distribution

```hcl
resource "aws_cloudfront_origin_access_control" "my-oac" {
  name                              = "my-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "my-distribution" {
  origin {
    domain_name              = aws_s3_bucket.my-bucket.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.my-bucket.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.my-oac.id
  }

  enabled             = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${aws_s3_bucket.my-bucket.id}"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

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
```

### Step 4 — Define your bucket policy

Create a `bucket_policy.tpl` file:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudfront.amazonaws.com"
      },
      "Action": "s3:GetObject",
      "Resource": "${bucket_arn}/*",
      "Condition": {
        "ArnLike": {
          "AWS:SourceArn": "${distribution_arn}"
        }
      }
    }
  ]
}
```

Then reference it in `main.tf`:

```hcl
resource "aws_s3_bucket_policy" "my-bucket-policy" {
  bucket = aws_s3_bucket.my-bucket.id
  policy = templatefile("${path.module}/bucket_policy.tpl", {
    bucket_arn       = aws_s3_bucket.my-bucket.arn
    distribution_arn = aws_cloudfront_distribution.my-distribution.arn
  })
}
```

### Step 5 — Upload your site files

```hcl
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.my-bucket.id
  key          = "index.html"
  source       = "${path.module}/index.html"
  content_type = "text/html"
}

resource "aws_s3_object" "error" {
  bucket       = aws_s3_bucket.my-bucket.id
  key          = "404.html"
  source       = "${path.module}/404.html"
  content_type = "text/html"
}
```

### Step 6 — Apply

```bash
terraform apply
```

Verify the site loads at your CloudFront URL before moving to Phase 3.

---

## Phase 3 — CI/CD Pipeline with GitHub Actions and OIDC

The goal is to automate deployments so every push to `main` deploys the site automatically using keyless OIDC authentication.

### Step 1 — Create the OIDC identity provider and IAM role in Terraform

Add to `main.tf`:

```hcl
resource "aws_iam_openid_connect_provider" "github" {
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
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:YOUR_GITHUB_USERNAME/YOUR_REPO_NAME:*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_policy" "github-actions" {
  name = "github-actions"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:ListBucket", "s3:DeleteObject", "s3:PutObject"]
        Resource = [
          aws_s3_bucket.my-bucket.arn,
          "${aws_s3_bucket.my-bucket.arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = "cloudfront:CreateInvalidation"
        Resource = aws_cloudfront_distribution.my-distribution.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github-actions" {
  role       = aws_iam_role.github-actions-role.name
  policy_arn = aws_iam_policy.github-actions.arn
}
```

Replace `YOUR_GITHUB_USERNAME/YOUR_REPO_NAME` with your actual values.

Run `terraform apply`.

### Step 2 — Add Terraform outputs

Create an `output.tf` file:

```hcl
output "github_actions_role_arn" {
  value = aws_iam_role.github-actions-role.arn
}

output "bucket_name" {
  value = aws_s3_bucket.my-bucket.id
}

output "distribution_id" {
  value = aws_cloudfront_distribution.my-distribution.id
}
```

Run `terraform output` to get your values.

### Step 3 — Add GitHub repository variables

In your GitHub repo go to **Settings → Secrets and variables → Actions → Variables** and add:

| Variable | Value |
|---|---|
| `AWS_ROLE_ARN` | Output from `terraform output github_actions_role_arn` |
| `AWS_REGION` | Your AWS region (e.g. `us-east-1`) |
| `BUCKET_NAME` | Output from `terraform output bucket_name` |
| `DISTRIBUTION_ID` | Output from `terraform output distribution_id` |

### Step 4 — Create the GitHub Actions workflow

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy to Production

on:
  push:
    branches:
      - main

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: ${{ vars.AWS_REGION }}

      - name: Sync files to S3
        run: |
          aws s3 sync . s3://${{ vars.BUCKET_NAME }} --exclude "*" --include "*.html" --delete

      - name: Invalidate CloudFront cache
        run: |
          aws cloudfront create-invalidation --distribution-id ${{ vars.DISTRIBUTION_ID }} --paths "/*"
```

Push to `main` and verify the workflow runs successfully in the **Actions** tab.

---

## Phase 4 — Staging Environment

The goal is to create a completely separate staging environment that deploys from a `staging` branch.

### Step 1 — Create staging infrastructure

Create a `staging.tf` file mirroring your `main.tf` but with staging-specific resource names and a different bucket name. Update your IAM policy in `main.tf` to include the staging bucket and distribution ARNs.

### Step 2 — Add staging GitHub variables

Add two more variables in GitHub:

| Variable | Value |
|---|---|
| `STAGING_BUCKET_NAME` | Your staging bucket name |
| `STAGING_DISTRIBUTION_ID` | Your staging CloudFront distribution ID |

### Step 3 — Create the staging workflow

Create `.github/workflows/deploy-staging.yml`:

```yaml
name: Deploy to Staging

on:
  push:
    branches:
      - staging

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: ${{ vars.AWS_REGION }}

      - name: Sync files to S3
        run: |
          aws s3 sync . s3://${{ vars.STAGING_BUCKET_NAME }} --exclude "*" --include "*.html" --delete

      - name: Invalidate CloudFront cache
        run: |
          aws cloudfront create-invalidation --distribution-id ${{ vars.STAGING_DISTRIBUTION_ID }} --paths "/*"
```

### Step 4 — Create the staging branch

```bash
git checkout -b staging
git push origin staging
```

Any push to the `staging` branch will now deploy to the staging environment independently of production.

---

## Typical Development Workflow

1. Make changes on the `staging` branch
2. Push to `staging` — deploys automatically to staging
3. Verify changes at the staging CloudFront URL
4. Merge `staging` into `main` — deploys automatically to production

---

## Tear Down

To destroy all AWS infrastructure:

```bash
terraform destroy
```

Your GitHub repository and files are not affected.

---

## Common Issues

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for a full list of issues encountered during this build and how they were resolved.