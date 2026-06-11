# AWS Static Website Deployment Pipeline

A production-style CI/CD pipeline that automatically deploys a static website to AWS on every code push. Built to demonstrate real-world cloud engineering practices including infrastructure as code, keyless authentication, and environment separation.

---

## What This Project Does

Every time code is pushed to GitHub, a fully automated pipeline:
1. Authenticates with AWS securely using OIDC — no stored credentials
2. Syncs the site files to a private S3 bucket
3. Invalidates the CloudFront cache so changes go live immediately

There are two independent environments — **production** (deploys from `main`) and **staging** (deploys from `staging`) — each with their own S3 bucket and CloudFront distribution.

---

## Technologies Used

| Technology | Purpose |
|---|---|
| AWS S3 | Private static file storage |
| AWS CloudFront | HTTPS content delivery with Origin Access Control (OAC) |
| AWS IAM + OIDC | Keyless authentication for GitHub Actions |
| Terraform | Infrastructure as Code — all AWS resources defined and managed in code |
| GitHub Actions | CI/CD pipeline — automated deployments on push |

---

## Architecture

```
GitHub Repo
    │
    ├── push to main ──────► GitHub Actions (deploy.yml)
    │                               │
    └── push to staging ───► GitHub Actions (deploy-staging.yml)
                                    │
                              AWS IAM (OIDC)
                              No stored credentials
                                    │
                    ┌───────────────┴───────────────┐
                    │                               │
             Production S3                    Staging S3
             (private bucket)              (private bucket)
                    │                               │
            CloudFront (OAC)              CloudFront (OAC)
                    │                               │
              Public HTTPS                   Public HTTPS
```

---

## Key Engineering Decisions

**OAC over public S3** — The S3 bucket is fully private. CloudFront accesses it using Origin Access Control, meaning files are never publicly accessible directly from S3. This is the current AWS best practice over the older OAI method.

**OIDC over IAM access keys** — Instead of storing long-lived AWS credentials in GitHub, the pipeline uses OpenID Connect. GitHub generates a short-lived token at runtime, AWS validates it, and issues temporary credentials scoped to this repo only. Nothing to rotate, nothing to leak.

**Terraform for everything** — All AWS infrastructure is defined in code. Tearing down and rebuilding the entire stack takes one command. Nothing was left as a manual console click.

**Least privilege IAM** — The IAM role only has the exact permissions needed: `s3:PutObject`, `s3:DeleteObject`, `s3:ListBucket`, and `cloudfront:CreateInvalidation`. Nothing more.

**Environment separation** — Production and staging are completely independent stacks. A broken staging deployment cannot affect the live site.

---

## Project Structure

```
aws-cloud-project-1/
├── .github/
│   └── workflows/
│       ├── deploy.yml              # Production pipeline (main branch)
│       └── deploy-staging.yml      # Staging pipeline (staging branch)
├── main.tf                         # Production infrastructure (Terraform)
├── staging.tf                      # Staging infrastructure (Terraform)
├── output.tf                       # Terraform outputs
├── bucket_policy.tpl               # S3 bucket policy template
├── index.html                      # Site entry point
├── 404.html                        # Custom error page
├── .gitignore
└── README.md
```

---

## What I Learned

- How CloudFront OAC works and why it replaced OAI as the AWS standard
- How OIDC federation works between GitHub and AWS — the full token exchange flow
- How Terraform manages state and why infrastructure as code matters
- Debugging real AWS errors — 403 vs 404 behavior with private S3 buckets, Content-Type metadata issues, IAM policy scoping
- How CI/CD pipelines are structured in production environments
- The importance of environment separation and why staging exists

---

## Troubleshooting

A log of real issues encountered during this build and how they were resolved is documented in [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

---

## Want to Build This Yourself?

A detailed step by step setup guide is available in [SETUP.md](SETUP.md).