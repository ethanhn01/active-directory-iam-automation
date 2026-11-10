# No third-party testing framework required. Runs cross-platform on PowerShell 7.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../src/IAMLab.psm1') -Force

$testCount = 0
function Assert-True {
    param([bool]$Condition, [string]$Message)
    $script:testCount++
    if (-not $Condition) { throw "FAILED: $Message" }
    Write-Host "PASS: $Message"
}
function Assert-Throws {
    param([scriptblock]$Action, [string]$Message)
    $script:testCount++
    $thrown = $false
    try { & $Action | Out-Null } catch { $thrown = $true }
    if (-not $thrown) { throw "FAILED: $Message" }
    Write-Host "PASS: $Message"
}

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$config = Join-Path $root 'config/lab.config.json'
$hires = Join-Path $root 'data/new-hires.csv'
$activations = Join-Path $root 'data/activate.csv'
$offboarding = Join-Path $root 'data/offboarding.csv'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('iam-lab-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force | Out-Null
$state = Join-Path $temp 'mock-state.json'
try {
    Initialize-IamMockState -StatePath $state | Out-Null
    Assert-True (Test-Path $state) 'Mock state initializes'

    $before = Get-Content -LiteralPath $state -Raw
    $plan = @(Invoke-IamOnboard -CsvPath $hires -ConfigPath $config -StatePath $state)
    $after = Get-Content -LiteralPath $state -Raw
    Assert-True ($plan.Count -eq 20 -and @($plan | Where-Object Status -eq 'Planned').Count -eq 20) 'Onboarding plan includes 20 employees'
    Assert-True ($before -ceq $after) 'Default onboarding plan performs no writes'

    $created = @(Invoke-IamOnboard -CsvPath $hires -ConfigPath $config -StatePath $state -Execute -Confirm:$false)
    Assert-True (@($created | Where-Object Status -eq 'CreatedDisabled').Count -eq 20) 'Onboarding creates 20 disabled mock users'
    $snapshot = Get-Content -LiteralPath $state -Raw | ConvertFrom-Json
    Assert-True (@($snapshot.users | Where-Object { $_.enabled -eq $true }).Count -eq 0) 'Onboarding never enables accounts automatically'
    Assert-True (@($snapshot.users | Where-Object { $_.groups.Count -eq 1 }).Count -eq 20) 'Each employee receives one approved group'

    $repeated = @(Invoke-IamOnboard -CsvPath $hires -ConfigPath $config -StatePath $state -Execute -Confirm:$false)
    Assert-True (@($repeated | Where-Object Status -eq 'AlreadyExists').Count -eq 20) 'Repeated onboarding is idempotent'

    $pending = @(Get-IamAccessAudit -ConfigPath $config -StatePath $state)
    Assert-True (@($pending | Where-Object Finding -eq 'PendingActivation').Count -eq 20) 'Audit shows pending activation rather than incorrectly treating staged accounts as offboarded'

    $before = Get-Content -LiteralPath $state -Raw
    $noop = @(Invoke-IamActivate -CsvPath $activations -ConfigPath $config -StatePath $state -Execute -WhatIf)
    Assert-True ((Get-Content -LiteralPath $state -Raw) -ceq $before) '-WhatIf prevents activation writes'
    Assert-True (@($noop | Where-Object Status -eq 'Skipped').Count -eq 20) '-WhatIf marks activation actions as skipped'

    $enabled = @(Invoke-IamActivate -CsvPath $activations -ConfigPath $config -StatePath $state -Execute -Confirm:$false)
    Assert-True (@($enabled | Where-Object Status -eq 'Activated').Count -eq 20) 'Explicit activation enables all 20 mock users'
    $audit = @(Get-IamAccessAudit -ConfigPath $config -StatePath $state)
    Assert-True (@($audit | Where-Object Finding -eq 'Compliant').Count -eq 20) 'Access audit reports correct managed access after activation'

    $before = Get-Content -LiteralPath $state -Raw
    $offPlan = @(Invoke-IamOffboard -CsvPath $offboarding -ConfigPath $config -StatePath $state)
    Assert-True (@($offPlan | Where-Object Status -eq 'Planned').Count -eq 2) 'Offboarding plans two users'
    Assert-True ((Get-Content -LiteralPath $state -Raw) -ceq $before) 'Offboarding plan performs no writes'
    $offResults = @(Invoke-IamOffboard -CsvPath $offboarding -ConfigPath $config -StatePath $state -Execute -Confirm:$false)
    Assert-True (@($offResults | Where-Object Status -eq 'Offboarded').Count -eq 2) 'Offboarding disables two users and revokes managed groups'
    $snapshot = Get-Content -LiteralPath $state -Raw | ConvertFrom-Json
    $disabled = @($snapshot.users | Where-Object { $_.enabled -eq $false })
    Assert-True ($disabled.Count -eq 2 -and @($disabled | Where-Object { $_.groups.Count -ne 0 }).Count -eq 0) 'Offboarded users have no managed access'
    $repeatOff = @(Invoke-IamOffboard -CsvPath $offboarding -ConfigPath $config -StatePath $state -Execute -Confirm:$false)
    Assert-True (@($repeatOff | Where-Object Status -eq 'AlreadyOffboarded').Count -eq 2) 'Repeated offboarding is idempotent'
    $audit = @(Get-IamAccessAudit -ConfigPath $config -StatePath $state)
    Assert-True (@($audit | Where-Object Finding -eq 'Compliant').Count -eq 20) 'Audit remains clean after offboarding'
    $blocked = @(Invoke-IamActivate -CsvPath $offboarding -ConfigPath $config -StatePath $state -Execute -Confirm:$false)
    Assert-True (@($blocked | Where-Object Status -eq 'Blocked').Count -eq 2) 'Offboarded users cannot be reactivated via pending workflow'


    # Deliberate simulated privilege violation for detection test.
    $snapshot = Get-Content -LiteralPath $state -Raw | ConvertFrom-Json
    $u = @($snapshot.users | Where-Object samAccountName -eq 'jmorris')[0]
    $u.groups = @('GG-Finance-Standard')
    $snapshot | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $state -Encoding UTF8
    $findings = @(Get-IamAccessAudit -ConfigPath $config -StatePath $state | Where-Object { $_.SamAccountName -eq 'jmorris' })
    Assert-True (@($findings | Where-Object Finding -eq 'MissingExpectedGroup').Count -eq 1) 'Audit catches missing approved group'
    Assert-True (@($findings | Where-Object Finding -eq 'UnexpectedManagedGroup').Count -eq 1) 'Audit catches excess managed privilege'

    # Input validation rejects unauthorized department without writing state.
    $badCsv = Join-Path $temp 'bad.csv'
    @('employeeId,firstName,lastName,samAccountName,department','E0999,Fictional,Person,fperson,SuperAdmins') |
        Set-Content -LiteralPath $badCsv -Encoding UTF8
    Assert-Throws { Invoke-IamOnboard -CsvPath $badCsv -ConfigPath $config -StatePath $state -Execute -Confirm:$false } 'Unknown department is rejected'
    $badDup = Join-Path $temp 'duplicates.csv'
    @('employeeId,firstName,lastName,samAccountName,department','E0998,Fictional,Person,fp1,IT','E0998,Second,Person,fp2,IT') |
        Set-Content -LiteralPath $badDup -Encoding UTF8
    Assert-Throws { Invoke-IamOnboard -CsvPath $badDup -ConfigPath $config -StatePath $state -Execute -Confirm:$false } 'Duplicate employee ID is rejected'

    Write-Host "`nAll $testCount assertions passed."
}
finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
