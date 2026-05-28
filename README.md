# AWS Static Website Deployment Pipeline

A production-style static website hosted on AWS using S3 and CloudFront, with infrastructure managed by Terraform and automated deployments via GitHub Actions.

## Architecture

```
GitHub Repo → GitHub Actions → S3 (private) → CloudFront → Users
```

- **S3** — Private bucket storing the static site files
- **CloudFront** — CDN that serves the site over HTTPS using Origin Access Control (OAC)
- **Terraform** — All infrastructure defined and managed as code
- **GitHub Actions** — CI/CD pipeline that deploys on every push to `main`
- **OIDC** — Keyless authentication between GitHub Actions and AWS (no static credentials)

## Project Structure

```
aws-cloud-project-1/
├── .github/
│   └── workflows/
│       └── deploy.yml       # GitHub Actions deployment workflow
├── .gitignore
├── main.tf                  # Terraform infrastructure code
├── outputs.tf               # Terraform outputs
├── bucket_policy.tpl        # S3 bucket policy template
├── index.html               # Static site entry point
└── README.md
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) installed
- [AWS CLI](https://aws.amazon.com/cli/) installed and configured
- An AWS account
- A GitHub account

## Infrastructure

All infrastructure is managed via Terraform and includes:

- S3 bucket with versioning and block public access enabled
- CloudFront distribution with OAC for secure S3 access
- IAM OIDC identity provider for GitHub Actions authentication
- IAM role and policy scoped to the minimum permissions required

## Deployment

### Initial Setup

1. Clone the repository
```bash
git clone https://github.com/dabanks213-max/aws-cloud-project-1.git
cd aws-cloud-project-1
```

2. Initialize and apply Terraform
```bash
terraform init
terraform apply
```

3. Add the following variables to your GitHub repo under **Settings → Secrets and variables → Actions → Variables**:

| Variable | Description |
|---|---|
| `AWS_ROLE_ARN` | ARN of the GitHub Actions IAM role |
| `AWS_REGION` | AWS region (e.g. `us-east-1`) |
| `BUCKET_NAME` | S3 bucket name |
| `DISTRIBUTION_ID` | CloudFront distribution ID |

You can get these values by running:
```bash
terraform output
```

### Automatic Deployments

Once set up, any push to the `main` branch will automatically:
1. Sync files to S3
2. Invalidate the CloudFront cache

### Tearing Down Infrastructure

```bash
terraform destroy
```

Note: Your GitHub repository and workflow files are unaffected by `terraform destroy`.

## Security

- S3 bucket is fully private — block public access is enabled
- CloudFront accesses S3 via OAC (Origin Access Control)
- GitHub Actions authenticates via OIDC — no long-lived AWS credentials stored anywhere
- IAM role is scoped to the minimum permissions needed and locked to this specific repository

## Phases

- **Phase 1** — Manual AWS setup (S3 + CloudFront + OAC)
- **Phase 2** — Infrastructure as Code with Terraform
- **Phase 3** — CI/CD pipeline with GitHub Actions and OIDC
- **Phase 4** — Hardening (S3 versioning, staging environment, custom error pages)
