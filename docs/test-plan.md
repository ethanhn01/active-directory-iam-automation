# Test plan and verification checklist

## Automated offline scenarios

Run `./tests/Run-Tests.ps1` in PowerShell. It uses a unique temporary folder and does **not** access Active Directory.

| Scenario | Expected behavior |
|---|---|
| Initialize mock | New state contains an empty `users` array |
| Default onboarding | 20 planned actions, no file changes |
| Execute onboarding | 20 disabled accounts with exactly the mapped group |
| Repeat onboarding | 20 `AlreadyExists`, no duplicates |
| Audit pending users | 20 `PendingActivation` informational results |
| Activation `-WhatIf` | No state changes |
| Execute activation | 20 enabled accounts |
| Audit active users | 20 compliant access results |
| Default offboarding | Two planned actions and no state changes |
| Execute offboarding | Both accounts disabled; managed groups revoked |
| Repeat offboarding | Both return `AlreadyOffboarded` |
| Audit post-offboarding | 20 compliant access results |
| Inject wrong managed group | Missing expected + unexpected group findings |
| Unapproved department | CSV is rejected before any onboarding |
| Duplicate employee ID | CSV is rejected before any onboarding |

GitHub Actions workflow: `.github/workflows/test.yml`, using the same dependency-free test script.

## Manual verification checklist

- [ ] Onboarding preview shows 20 fictional identities without writing.
- [ ] Mock onboarding creates disabled accounts, not enabled accounts.
- [ ] Activation requires the separate `-Execute` step.
- [ ] Offboarding disables two accounts and removes only project-managed groups.
- [ ] The generated access-audit CSV has 20 compliant rows after the clean workflow.
- [ ] An intentionally added cross-department group produces a High-severity finding.
- [ ] A repeated run does not create duplicate accounts.
- [ ] Source control contains no generated state, secrets, or real employee data.
- [ ] If testing real AD, only the dedicated isolated lab OU and groups are affected.
- [ ] After pushing to GitHub, the test workflow completes successfully.

## Evidence logging (fill in after running)

| Date | Environment | Test | Result | Evidence |
|---|---|---|---|---|
| *Not yet run by project owner* | Mock | All assertions | Pending | Add actual CI run link |
| *Not yet run by project owner* | Isolated AD VM | Onboard/activate/offboard | Pending | Add sanitized screenshots |

Do not report the test suite as passed on your resume until you have actually executed it and checked the results.
