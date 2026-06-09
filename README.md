# AWS Static Website Deployment Pipeline

A production-style static website hosted on AWS using S3 and CloudFront, with infrastructure managed by Terraform and automated deployments via GitHub Actions using keyless OIDC authentication.

---

## Architecture

```
GitHub Repo → GitHub Actions (OIDC) → S3 (private) → CloudFront (OAC) → Users
```

- **S3** — Private bucket storing static site files with versioning enabled
- **CloudFront** — CDN that serves the site over HTTPS using Origin Access Control (OAC)
- **Terraform** — All infrastructure defined and managed as code
- **GitHub Actions** — CI/CD pipeline that deploys automatically on every push to `main`
- **OIDC** — Keyless authentication between GitHub Actions and AWS — no static credentials stored anywhere

---

## Project Structure

```
aws-cloud-project-1/
├── .github/
│   └── workflows/
│       └── deploy.yml          # GitHub Actions deployment workflow
├── .gitignore
├── main.tf                     # Terraform infrastructure code
├── output.tf                   # Terraform outputs
├── bucket_policy.tpl           # S3 bucket policy template
├── index.html                  # Static site entry point
├── 404.html                    # Custom error page
└── README.md
```

---

## Infrastructure

All infrastructure is managed via Terraform and includes:

- S3 bucket with versioning enabled and block public access enforced
- CloudFront distribution with OAC for secure private S3 access
- Custom error responses for 403 and 404 errors serving a clean HTML error page
- IAM OIDC identity provider for GitHub Actions authentication
- IAM role and policy with least privilege permissions scoped to this repo only

---

## Phases

### Phase 1 — Manual AWS Setup
Manually created the core AWS infrastructure to understand how the pieces fit together before automating anything:
- Created a private S3 bucket with block public access enabled
- Created a CloudFront distribution using Origin Access Control (OAC) to securely serve content from the private bucket
- Configured the S3 bucket policy to allow CloudFront service principal access, scoped to the specific distribution ARN
- Verified the site loads over HTTPS using the default CloudFront domain (`*.cloudfront.net`)

### Phase 2 — Infrastructure as Code with Terraform
Recreated the entire infrastructure in Terraform so it is repeatable, version controlled, and reproducible with a single command:
- Defined S3 bucket, CloudFront distribution, OAC, and bucket policy as Terraform resources
- Used `templatefile()` to dynamically inject resource ARNs into the bucket policy template
- Used `${path.module}` for reliable file path references
- Added `force_destroy = true` to allow clean teardown of non-empty buckets
- Verified `terraform destroy` and `terraform apply` rebuild the full stack cleanly

### Phase 3 — CI/CD Pipeline with GitHub Actions and OIDC
Automated deployments so every push to `main` deploys the site without any manual steps:
- Configured an IAM OIDC identity provider in AWS trusting `token.actions.githubusercontent.com`
- Created an IAM role with a trust policy scoped to this specific GitHub repo
- Attached a least privilege IAM policy allowing only the actions needed to deploy
- Wrote `deploy.yml` to sync HTML files to S3 and invalidate CloudFront cache on every push to `main`
- Used GitHub repository variables to avoid hardcoding any AWS resource IDs in the workflow

### Phase 4 — Hardening
Tightened up the infrastructure with production best practices:
- Enabled S3 versioning for rollback capability on every object
- Added custom `403` and `404` error responses in CloudFront serving a clean HTML error page
- Updated the GitHub Actions sync command to only upload HTML files, preventing Terraform and config files from leaking into the S3 bucket
- Staging environment in progress

---

## Setup

### Prerequisites
- [Terraform](https://developer.hashicorp.com/terraform/install) installed
- [AWS CLI](https://aws.amazon.com/cli/) installed and configured
- An AWS account
- A GitHub account

### Deploy Infrastructure

```bash
git clone https://github.com/dabanks213-max/aws-cloud-project-1.git
cd aws-cloud-project-1
terraform init
terraform apply
```

### Configure GitHub Variables

After applying, run `terraform output` and add the following to your GitHub repo under **Settings → Secrets and variables → Actions → Variables**:

| Variable | Description |
|---|---|
| `AWS_ROLE_ARN` | ARN of the GitHub Actions IAM role |
| `AWS_REGION` | AWS region (e.g. `us-east-1`) |
| `BUCKET_NAME` | S3 bucket name |
| `DISTRIBUTION_ID` | CloudFront distribution ID |

### Deploy Site

Push any change to `main` and GitHub Actions will automatically sync files to S3 and invalidate the CloudFront cache.

To trigger a deployment without changing files:
```bash
git commit --allow-empty -m "Trigger deployment"
git push origin main
```

### Tear Down

```bash
terraform destroy
```

Note: Your GitHub repository and workflow files are not affected by `terraform destroy`.

---

## Security

- S3 bucket is fully private — block public access is enabled on all settings
- CloudFront accesses S3 exclusively via OAC — no public bucket access required
- GitHub Actions authenticates via OIDC — no long-lived AWS credentials stored anywhere
- IAM role trust policy is locked to this specific GitHub repository
- IAM permissions follow least privilege — only the exact actions needed are granted

---

## Troubleshooting

### CloudFront returning 403 Access Denied
**Cause:** The `origin_access_control_id` was missing from the CloudFront origin block in Terraform, so CloudFront couldn't authenticate with S3.
**Fix:** Added `origin_access_control_id = aws_cloudfront_origin_access_control.my-oac.id` to the origin block.

### index.html downloading instead of rendering
**Cause:** The file was uploaded to S3 without the correct `Content-Type`, defaulting to `application/octet-stream`.
**Fix:** Added `content_type = "text/html"` to the `aws_s3_object` resource in Terraform.

### JSON syntax error in bucket policy template
**Cause:** Missing comma after the `Resource` field in `bucket_policy.tpl`.
**Fix:** Added the missing comma — every key:value pair in JSON requires a comma except the last one.

### Terraform variables not resolving in bucket policy
**Cause:** Raw JSON strings don't support Terraform interpolation.
**Fix:** Used `templatefile()` with a `.tpl` file to inject resource ARNs dynamically at apply time.

### GitHub Actions OIDC authentication failing
**Cause:** The `permissions` block was missing from `deploy.yml`, preventing GitHub from generating an OIDC token.
**Fix:** Added `id-token: write` to the permissions block in the workflow.

### Custom 404 page not showing — still seeing XML error
**Cause:** CloudFront returns a 403 (not a 404) when an object doesn't exist in a private S3 bucket. The `custom_error_response` block only handled 404.
**Fix:** Added a second `custom_error_response` block mapping 403 errors to the custom `404.html` page.

### Terraform files appearing in S3 bucket
**Cause:** The GitHub Actions sync command was syncing the entire repo root, uploading Terraform and config files alongside site files.
**Fix:** Updated the sync command to `--exclude "*" --include "*.html" --delete` to only upload HTML files.
