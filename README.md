# Azure DevSecOps Pipeline

**Secure Terraform Deployment with Policy Gates**

[![Checkov Scan](https://github.com/ekaumoh/devsecops-azure-pipeline/actions/workflows/checkov-scan.yml/badge.svg)](https://github.com/ekaumoh/devsecops-azure-pipeline/actions/workflows/checkov-scan.yml)
![Terraform](https://img.shields.io/badge/Terraform-844FBA?logo=terraform&logoColor=white)
![Azure](https://img.shields.io/badge/Azure-0078D4?logo=microsoftazure&logoColor=white)
![OIDC](https://img.shields.io/badge/Auth-OIDC%20Federation-2ea44f)

A shift-left DevSecOps pipeline that scans Terraform infrastructure code for security misconfigurations **before** any resources reach Azure. Every pull request triggers a Checkov scan against CIS/NIST controls. Insecure code is hard-blocked from merging. Clean code deploys via Terraform using passwordless OIDC federation to a least-privilege Azure identity, with runtime threat detection through Microsoft Defender for Storage and SIEM coverage via Microsoft Sentinel unified with Defender XDR.

---

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Developer     │───▶│   Pull Request  │───▶│  Checkov Scan   │
│  (feature/*)    │    │   (main target) │    │   (CIS/NIST)    │
└─────────────────┘    └─────────────────┘    └────────┬────────┘
                                                       │
                              ┌────────────────────────┴────────────────────────┐
                              ▼                                                 ▼
                       ┌─────────────┐                                  ┌──────────────┐
                       │  FAIL: Merge│                                  │ PASS: Branch │
                       │   BLOCKED   │                                  │  Protection  │
                       └─────────────┘                                  │   Allows     │
                                                                        │    Merge     │
                                                                        └──────┬───────┘
                                                                               ▼
                                                                ┌──────────────────────┐
                                                                │  GitHub Actions      │
                                                                │  → OIDC Token        │
                                                                │  → Entra ID          │
                                                                │  → Azure Access Token│
                                                                └──────┬───────────────┘
                                                                       ▼
                                                                ┌──────────────────────┐
                                                                │  Terraform Apply     │
                                                                │  (RG-scoped RBAC)    │
                                                                └──────┬───────────────┘
                                                                       ▼
                                                          ┌─────────────────────────────┐
                                                          │  Azure Resources Deployed   │
                                                          │  + Defender for Storage     │
                                                          │  + Sentinel/Log Analytics   │
                                                          │  + Defender XDR Integration │
                                                          └─────────────────────────────┘
```

| Stage | Tool | What happens |
|---|---|---|
| Pre-deployment scan | Checkov | Scans Terraform files against CIS/NIST controls on every PR |
| Gate enforcement | GitHub Branch Protection | Blocks merge if Checkov fails — **hard enforcement, not advisory** |
| Authentication | OIDC Federation (GitHub ↔ Entra ID) | GitHub Actions exchanges a short-lived OIDC token for an Azure access token — **no stored secrets** |
| Authorization | Azure RBAC (least privilege) | Service principal scoped to the deployment RG only, not the subscription |
| Provisioning | Terraform | Init → Plan → Apply on merge to `main` |
| State management | Azure Blob Backend | Terraform state persisted with AzureAD + OIDC auth (no access keys) |
| Runtime threat detection | Microsoft Defender for Storage | Behavioral monitoring on deployed storage accounts |
| SIEM | Microsoft Sentinel + Defender XDR | Log Analytics workspace ingests telemetry; Sentinel onboarded as Primary workspace to Defender XDR for unified SOC experience |

---

## Security Controls Enforced

Checkov validates 11 controls on every run. Three are intentionally soft-failed with documented justification.

| Checkov Check | Control | Implementation | Status |
|---|---|---|---|
| CKV_AZURE_190 / CKV2_AZURE_47 | No public blob access | `allow_nested_items_to_be_public = false` | ✅ ENFORCED |
| CKV_AZURE_3 | HTTPS only | `https_traffic_only_enabled = true` | ✅ ENFORCED |
| CKV_AZURE_44 | Minimum TLS 1.2 | `min_tls_version = "TLS1_2"` | ✅ ENFORCED |
| CKV_AZURE_59 | Public network access disabled | `public_network_access_enabled = false` | ✅ ENFORCED |
| CKV2_AZURE_40 | Shared Key auth disabled | `shared_access_key_enabled = false` | ✅ ENFORCED |
| CKV2_AZURE_41 | SAS token expiration policy | `sas_policy expiration_period = 1 hour` | ✅ ENFORCED |
| CKV2_AZURE_38 | Blob soft delete | `delete_retention_policy days = 7` | ✅ ENFORCED |
| CKV_AZURE_33 | Queue service logging | `queue_properties` logging read/write/delete = true | ✅ ENFORCED |
| CKV_AZURE_206 | Geo-redundant replication | LRS used — GRS cost not justified for demo | ⚠️ SOFT-FAIL |
| CKV2_AZURE_33 | Private endpoint | Requires full VNet — out of scope for portfolio demo | ⚠️ SOFT-FAIL |
| CKV2_AZURE_1 | Customer Managed Keys | Requires Key Vault wiring — planned stretch goal | ⚠️ SOFT-FAIL |

---

## Identity & Access

### OIDC Federation (no stored secrets)

GitHub Actions and Entra ID are wired with a federated credential. On every workflow run, GitHub mints a short-lived OIDC token that Entra ID exchanges for an Azure access token. **The pipeline holds no long-lived credentials.**

| Federated Credential Property | Value |
|---|---|
| Issuer | `https://token.actions.githubusercontent.com` |
| Subject | `repo:ekaumoh/devsecops-azure-pipeline:ref:refs/heads/main` |
| Audience | `api://AzureADTokenExchange` |
| Workflow permission | `id-token: write` |
| Terraform flag | `ARM_USE_OIDC=true` on provider **and** backend |

### Least-Privilege RBAC

The service principal `sp-devsecops-pipeline` holds the minimum role assignments needed for the pipeline to function. **No subscription-level Contributor.**

| Role | Scope | Purpose |
|---|---|---|
| Contributor | `/resourceGroups/rg-devsecops-demo` | Deploy and manage resources in the target RG only |
| Storage Blob Data Contributor | `stterraformstate18262` | Read/write Terraform state via Entra ID, not access keys |
| Reader | `/resourceGroups/rg-terraform-state` | Discover the backend container at init time |

---

## Runtime Security & SIEM

| Component | Resource | Function |
|---|---|---|
| Microsoft Defender for Storage | Enabled at subscription (DefenderForStorageV2 plan) | Behavioral threat detection — anomalous access, malware uploads, suspicious operations |
| Log Analytics Workspace | `law-devsecops-demo` (East US, PerGB2018, 30-day retention) | Telemetry sink for Azure resources |
| Microsoft Sentinel | Onboarded to `law-devsecops-demo` | SIEM and SOAR — analytic rules, hunting, automation |
| Defender XDR ↔ Sentinel | `law-devsecops-demo` connected as Primary workspace | Unified incident queue — Defender alerts flow into Sentinel automatically |

---

## Tech Stack

| Tool | Purpose |
|---|---|
| Terraform | Infrastructure as Code — Azure resource provisioning |
| Checkov 3.2.521 | Static IaC security scanner (CIS/NIST benchmark checks) |
| GitHub Actions | CI/CD pipeline (`checkov-scan.yml`) |
| OIDC Federation | Passwordless GitHub Actions ↔ Azure authentication |
| Azure Service Principal | Least-privilege non-human identity |
| Azure Blob Backend | Persistent Terraform state with AzureAD + OIDC auth |
| GitHub Branch Protection | Hard merge enforcement — Checkov must pass before merge |
| Microsoft Defender for Storage | Runtime threat detection on deployed storage accounts |
| Microsoft Sentinel + Defender XDR | SIEM with unified incident queue |

---

## Key Engineering Decisions

- **OIDC over client secrets** — federated credentials eliminate the need to rotate, store, or scope a long-lived shared secret. GitHub mints a token only at workflow runtime and Azure trusts it via the federation contract. Industry best practice for CI/CD-to-cloud authentication.
- **Least-privilege RBAC at the resource group, not subscription** — subscription-level Contributor was the path of least resistance during initial bring-up but represents excessive blast radius. The pipeline only needs to manage one RG; the role assignment now reflects that.
- **`storage_use_azuread = true`** in `providers.tf` — required to align the Terraform Azure provider with `shared_access_key_enabled = false`. Without this, the provider attempts key-based health checks on the storage account and fails with a 403 error.
- **`use_azuread_auth` + `use_oidc` on the backend block** — the provider's `ARM_USE_OIDC` env var doesn't propagate to backend init. Both flags must be declared explicitly in the backend configuration, or Terraform falls back to `listKeys` against the state storage account.
- **Soft-fail pattern** — three Checkov checks are downgraded to warnings rather than hard fails. A deliberate security engineering decision, not a bypass. Each has documented justification.
- **`needs: checkov`** in the pipeline — ensures the Terraform deploy job never starts until Checkov completes successfully. Defense in depth: prevents insecure code from reaching Azure even if branch protection is misconfigured.
- **`if: github.ref == refs/heads/main`** — Terraform only deploys on merge to `main`, never on PRs. Prevents infrastructure changes from feature branches.

---

## Real Debugging Encountered

- **403 KeyBasedAuthenticationNotPermitted (workload)** — Terraform provider tried to verify the workload storage account using key auth after setting `shared_access_key_enabled = false`. Fixed by adding `storage_use_azuread = true` to provider config.
- **403 KeyBasedAuthenticationNotPermitted (backend)** — Same error class on the state storage account during `terraform init`. Root cause: provider's `ARM_USE_OIDC` env var doesn't propagate to the backend. Fixed by adding `use_azuread_auth = true` and `use_oidc = true` to the backend block in `providers.tf`.
- **State conflict on re-run** — resource group already existed from a failed prior run but Terraform had no state file, causing a duplicate resource error. Fixed by adding the Azure blob backend for persistent state.
- **Pipeline didn't trigger on feature branch push** — the scan job is gated on `pull_request` events. Pushing to a feature branch alone is insufficient; opening or updating a PR is the trigger.

---

## Project Status

- [x] Terraform IaC with 8 enforced security controls
- [x] Checkov local scan — 11 passing, 3 intentional soft-fails
- [x] GitHub Actions pipeline on push and pull request
- [x] Branch protection enforcing required Checkov pass
- [x] Azure deployment via service principal
- [x] Persistent Terraform state via Azure blob backend
- [x] **OIDC federation — no stored client secrets**
- [x] **Least-privilege RBAC scope (RG-level Contributor, not subscription)**
- [x] **Microsoft Defender for Storage enabled (DefenderForStorageV2)**
- [x] **Log Analytics workspace `law-devsecops-demo` provisioned**
- [x] **Microsoft Sentinel onboarded and connected as Primary workspace to Defender XDR**
- [ ] Sentinel scheduled analytic rule (deferred — see note below)
- [ ] Customer Managed Keys via Key Vault (planned stretch)

> **Note on the deferred analytic rule:** Per [Microsoft Learn](https://learn.microsoft.com/en-us/azure/sentinel/create-analytics-rules?tabs=defender-portal) (updated May 2026), Microsoft Sentinel in the Azure portal is being fully retired March 31, 2027, with auto-migration to the Defender portal having begun July 2025. This tenant is mid-transition: the Azure portal Analytics blade shows *"This page was moved to Defender portal,"* while the Defender portal sidebar Analytics link is intermittently failing to navigate away from the SIEM Workspaces settings page. The workspace, data flow, and Defender XDR connection are all in place to receive a rule the moment portal navigation stabilizes.

---

## Repository Structure

```
devsecops-azure-pipeline/
├── .github/
│   └── workflows/
│       └── checkov-scan.yml          # CI/CD pipeline definition
├── terraform/
│   ├── providers.tf                  # Azure provider + OIDC backend config
│   ├── variables.tf                  # Input variables
│   └── main.tf                       # Storage account with enforced controls
└── README.md
```

---

## License

MIT