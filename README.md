# DevSecOps Azure Pipeline

A shift-left security pipeline that automatically scans Terraform infrastructure code for misconfigurations before any resources are deployed to Azure.

## What This Does

Every pull request to `main` triggers an automated Checkov security scan. If the Terraform code violates security policy, the pipeline fails and the merge is blocked. Secure code merges. Insecure code does not.

## Architecture

Developer pushes code → GitHub Actions triggers Checkov scan → Checkov validates Terraform against CIS/NIST controls → PASS: merge allowed, Terraform deploys to Azure | FAIL: merge blocked, developer must fix first

## Security Controls Enforced

| Control | Implementation |
|---|---|
| No public blob access | allow_nested_items_to_be_public = false |
| HTTPS only | https_traffic_only_enabled = true |
| Minimum TLS 1.2 | min_tls_version = "TLS1_2" |
| Public network access disabled | public_network_access_enabled = false |
| Shared Key auth disabled | shared_access_key_enabled = false |
| SAS token expiration policy | 1-hour expiration window |
| Blob soft delete | 7-day retention policy |
| Queue service logging | Full read/write/delete audit logging |

## Tech Stack

- **Terraform** — Infrastructure as Code for Azure resource provisioning
- **Checkov** — Static IaC security scanner (CIS/NIST benchmark checks)
- **GitHub Actions** — CI/CD pipeline automation
- **Azure** — Target cloud environment (Storage Account, Resource Group)
- **Branch Protection Rules** — Hard merge enforcement on main

## Pipeline in Action

The test/insecure-config branch in this repo demonstrates the gate working — a storage account with public blob access enabled fails the Checkov scan and is blocked from merging into main.

## Project Status

- [x] Terraform IaC with security controls
- [x] Checkov local scan (11 passing, 3 intentional soft-fails)
- [x] GitHub Actions pipeline on push and pull request
- [x] Branch protection enforcing required Checkov pass
- [ ] Azure deployment via service principal (in progress)
- [ ] Microsoft Defender for Cloud integration
- [ ] Microsoft Sentinel analytic rule