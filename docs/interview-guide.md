# Interview and portfolio walkthrough

## 60-second project explanation

> I built an IAM lifecycle automation lab using PowerShell. I simulated a 20-person company with IT, HR, Finance, and Operations. The scripts validate CSV requests, create accounts in a disabled state, assign allowlisted department groups, separately activate approved accounts, and disable/revoke managed access on offboarding. I also wrote an access audit that flags excess privileges or missing groups and added automated tests. I used fictional data, and the mock mode let me validate the workflow without touching a live directory.

Adapt this **only after actually running the workflow and understanding the code**.

## Five-minute demonstration plan

1. Explain the CSV input and group policy in `config/lab.config.json`.
2. Run `Initialize-Lab.ps1`, then onboarding without `-Execute` to show safe preview.
3. Run onboarding with `-Execute` and show accounts are disabled; then activate.
4. Offboard two fictional users, show the audit CSV.
5. Intentionally modify one **mock** user's groups and rerun the audit to show a finding; restore the state afterward.

## Questions you might be asked

**Why create disabled accounts first?** So provisioning and permission staging do not automatically grant an interactive sign-in before the identity and credentials are approved.

**How did you use least privilege?** Group assignments are sourced only from a fixed department allowlist. The offboarding script revokes only its own managed groups; it does not guess at or remove unrelated entitlements.

**How do you avoid deleting the wrong person?** The scripts require a match on two identifiers, validate input format, preview changes by default, and do not delete accounts at all.

**How do you handle failures?** This is a training project: missing inputs and identity mismatches throw errors. Mock writes are done once after processing a batch. Real AD provisioning is not transactional, so the code explicitly documents partial-failure recovery and a production-hardening backlog.

**Did you test it in production Active Directory?** Answer truthfully. If you ran only mock mode, say so. If you later built a domain controller lab and ran the adapter there, explain the exact steps and screenshots you personally verified.

## Resume example — only after testing

**Identity & Access Management Automation Lab** | PowerShell, Active Directory (lab adapter), RBAC, GitHub Actions

- Built a PowerShell IAM workflow for 20 simulated employees, covering disabled-first onboarding, approved activation, offboarding, and least-privilege group mapping.
- Developed CSV identity validation and account access reviews that flag missing or unexpected managed group memberships.
- Added a self-contained automated test suite and GitHub Actions workflow to validate lifecycle behavior and idempotency.

Don't list Windows Server / live AD execution as hands-on project experience until you personally build and test the optional server lab.
