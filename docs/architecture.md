# Architecture and security decisions

## Data flow

```mermaid
flowchart TD
    CSV["Synthetic HR CSV"] --> Validate["Validate required columns, identities, duplicates, departments"]
    Config["Allowlisted RBAC config"] --> Validate
    Validate --> Preview{"Explicit -Execute?"}
    Preview -->|No| Plan["Read-only plan"]
    Preview -->|Yes| Approval{"PowerShell ShouldProcess / -WhatIf"}
    Approval -->|No| Skip["No changes"]
    Approval -->|Yes| Provider{"Provider"}
    Provider --> Mock["Mock JSON state"]
    Provider --> AD["Isolated AD Lab OU"]
    Mock --> Audit["Access audit CSV"]
    AD --> Audit
