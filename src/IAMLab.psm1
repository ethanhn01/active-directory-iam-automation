Set-StrictMode -Version Latest

function Get-IamConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ConfigPath)
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "Config not found: $ConfigPath"
    }
    $config = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json
    foreach ($name in @('domainDnsName', 'organizationalUnit', 'groupsByDepartment', 'managedGroups')) {
        if ($null -eq $config.PSObject.Properties[$name]) { throw "Config is missing '$name'." }
    }
    if (@($config.managedGroups).Count -eq 0) { throw 'managedGroups cannot be empty.' }
    if (@($config.groupsByDepartment.PSObject.Properties).Count -eq 0) { throw 'No department mappings configured.' }
    foreach ($p in $config.groupsByDepartment.PSObject.Properties) {
        if (@($p.Value).Count -eq 0) { throw "No groups mapped for department '$($p.Name)'." }
        foreach ($g in @($p.Value)) {
            if (@($config.managedGroups) -notcontains $g) { throw "Group '$g' is not in managedGroups." }
        }
    }
    return $config
}

function Read-IamCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CsvPath,
        [Parameter(Mandatory)][ValidateSet('Onboard', 'Offboard')][string]$Operation,
        [Parameter(Mandatory)]$Config
    )
    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) { throw "CSV not found: $CsvPath" }
    $rows = @(Import-Csv -LiteralPath $CsvPath -ErrorAction Stop)
    if ($rows.Count -eq 0) { throw 'CSV cannot be empty.' }
    $required = @('employeeId', 'samAccountName')
    if ($Operation -eq 'Onboard') { $required += @('firstName', 'lastName', 'department') }
    foreach ($field in $required) {
        if ($null -eq $rows[0].PSObject.Properties[$field]) { throw "CSV is missing column '$field'." }
    }
    $seenId = @{}
    $seenSam = @{}
    foreach ($row in $rows) {
        foreach ($field in $required) {
            if ([string]::IsNullOrWhiteSpace([string]$row.$field)) { throw "CSV has blank '$field'." }
            $row.$field = ([string]$row.$field).Trim()
        }
        if ($row.employeeId -cnotmatch '^E[0-9]{4}$') { throw "Invalid employeeId '$($row.employeeId)' (expected E0001)." }
        if ($row.samAccountName -cnotmatch '^[a-z][a-z0-9._-]{1,19}$') { throw "Invalid samAccountName '$($row.samAccountName)' (2-20 lowercase safe characters)." }
        if ($seenId.ContainsKey($row.employeeId) -or $seenSam.ContainsKey($row.samAccountName)) {
            throw "Duplicate employee ID or username in CSV: $($row.employeeId) / $($row.samAccountName)"
        }
        $seenId[$row.employeeId] = $true
        $seenSam[$row.samAccountName] = $true
        if ($Operation -eq 'Onboard') {
            if ($row.firstName -cnotmatch "^[a-zA-Z][a-zA-Z '-]{0,49}$" -or $row.lastName -cnotmatch "^[a-zA-Z][a-zA-Z '-]{0,49}$") {
                throw "Invalid first/last name for $($row.samAccountName)."
            }
            if ($null -eq $Config.groupsByDepartment.PSObject.Properties[$row.department]) {
                throw "Department '$($row.department)' is not approved in config."
            }
        }
    }
    return $rows
}

function Get-IamMockState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StatePath)
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) { return [pscustomobject]@{ users = @() } }
    $state = Get-Content -LiteralPath $StatePath -Raw -ErrorAction Stop | ConvertFrom-Json
    if ($null -eq $state.PSObject.Properties['users']) { throw 'Mock state must contain a users array.' }
    return $state
}

function Save-IamMockState {
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)][string]$StatePath)
    $parent = Split-Path -Parent $StatePath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $json = ConvertTo-Json -InputObject $State -Depth 10
    # Write via a temporary file in the same directory, then replace the state.
    $temp = "$StatePath.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temp, $json + [Environment]::NewLine, ([System.Text.UTF8Encoding]::new($false)))
        Move-Item -LiteralPath $temp -Destination $StatePath -Force
    }
    finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
}

function Initialize-IamMockState {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$StatePath, [switch]$Force)
    if ((Test-Path -LiteralPath $StatePath) -and -not $Force) { throw "Mock state exists: $StatePath. Use -Force to reset it." }
    if ($PSCmdlet.ShouldProcess($StatePath, 'Initialize empty mock state')) {
        Save-IamMockState -State ([pscustomobject]@{ users = @() }) -StatePath $StatePath
        Write-Output "Initialized $StatePath"
    }
}

function Get-ManagedGroupsForDepartment {
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][string]$Department)
    return @($Config.groupsByDepartment.PSObject.Properties[$Department].Value)
}

function Find-MockUser {
    param($State, [string]$Sam, [string]$EmployeeId)
    return @($State.users | Where-Object { $_.samAccountName -eq $Sam -or $_.employeeId -eq $EmployeeId })
}

function Assert-ActiveDirectoryAvailable {
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw 'ActiveDirectory module missing. Use -Provider Mock, or install RSAT Active Directory tools in an isolated Windows lab.'
    }
    Import-Module ActiveDirectory -ErrorAction Stop
}

function Find-AdLabUser {
    param([Parameter(Mandatory)][string]$Sam, [Parameter(Mandatory)]$Config)
    # CSV validation ensures no LDAP-special characters enter this filter.
    $matches = @(Get-ADUser -LDAPFilter "(sAMAccountName=$Sam)" -SearchBase $Config.organizationalUnit -Properties Department, EmployeeID, MemberOf, Description -ErrorAction Stop)
    if ($matches.Count -gt 1) { throw "More than one lab user matched '$Sam'." }
    if ($matches.Count -eq 0) { return $null }
    return $matches[0]
}

function Invoke-IamOnboard {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$CsvPath,
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$StatePath,
        [ValidateSet('Mock', 'ActiveDirectory')][string]$Provider = 'Mock',
        [switch]$Execute
    )
    $config = Get-IamConfiguration -ConfigPath $ConfigPath
    $rows = @(Read-IamCsv -CsvPath $CsvPath -Operation Onboard -Config $config)
    if ($Provider -eq 'ActiveDirectory') { Assert-ActiveDirectoryAvailable }
    else { $state = Get-IamMockState -StatePath $StatePath }
    $changed = $false
    foreach ($row in $rows) {
        $sam = $row.samAccountName
        $groups = @(Get-ManagedGroupsForDepartment -Config $config -Department $row.department)
        if ($Provider -eq 'Mock') { $matches = @(Find-MockUser -State $state -Sam $sam -EmployeeId $row.employeeId) }
        else {
            $adUser = Find-AdLabUser -Sam $sam -Config $config
            $matches = @()
            if ($null -ne $adUser) { $matches = @($adUser) }
        }
        if ($matches.Count -gt 0) {
            if ($Provider -eq 'ActiveDirectory' -and $matches[0].EmployeeID -ne $row.employeeId) {
                throw "Existing lab AD username '$sam' does not match employee ID $($row.employeeId)."
            }
            # In Mock, a collision on either key is a hard stop: never overwrite another employee.
            if ($Provider -eq 'Mock' -and @($matches | Where-Object { $_.employeeId -ne $row.employeeId -or $_.samAccountName -ne $sam }).Count -gt 0) {
                throw "ID/username collision: $($row.employeeId) / $sam"
            }
            [pscustomobject]@{ EmployeeId = $row.employeeId; SamAccountName = $sam; Status = 'AlreadyExists'; Detail = 'No changes made' }
            continue
        }
        if (-not $Execute) {
            [pscustomobject]@{ EmployeeId = $row.employeeId; SamAccountName = $sam; Status = 'Planned'; Detail = "Create disabled user; assign $($groups -join ', ')" }
            continue
        }
        if (-not $PSCmdlet.ShouldProcess($sam, 'Create disabled lab account and assign approved groups')) {
            [pscustomobject]@{ EmployeeId = $row.employeeId; SamAccountName = $sam; Status = 'Skipped'; Detail = 'WhatIf or confirmation declined' }
            continue
        }
        if ($Provider -eq 'Mock') {
            $user = [pscustomobject]@{
                employeeId = $row.employeeId; samAccountName = $sam
                firstName = $row.firstName; lastName = $row.lastName; department = $row.department
                enabled = $false; groups = @($groups); lifecycleStatus = 'PendingActivation'
                createdAtUtc = [DateTime]::UtcNow.ToString('o'); disabledAtUtc = $null
            }
            $state.users = @($state.users) + @($user)
            $changed = $true
        }
        else {
            # Intentionally create DISABLED. Admin sets an initial password through an approved workflow.
            New-ADUser -Name "$($row.firstName) $($row.lastName) ($($row.employeeId))" `
                -GivenName $row.firstName -Surname $row.lastName -SamAccountName $sam `
                -UserPrincipalName "$sam@$($config.domainDnsName)" `
                -Department $row.department -Path $config.organizationalUnit `
                -OtherAttributes @{ employeeID = $row.employeeId } -Description 'IAMLAB:PendingActivation' -Enabled:$false -ErrorAction Stop
            foreach ($group in $groups) { Add-ADGroupMember -Identity $group -Members $sam -ErrorAction Stop }
        }
        [pscustomobject]@{ EmployeeId = $row.employeeId; SamAccountName = $sam; Status = 'CreatedDisabled'; Detail = "Approved groups: $($groups -join ', ')" }
    }
    if ($Provider -eq 'Mock' -and $changed) { Save-IamMockState -State $state -StatePath $StatePath }
}

function Invoke-IamOffboard {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$CsvPath,
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$StatePath,
        [ValidateSet('Mock', 'ActiveDirectory')][string]$Provider = 'Mock',
        [switch]$Execute
    )
    $config = Get-IamConfiguration -ConfigPath $ConfigPath
    $rows = @(Read-IamCsv -CsvPath $CsvPath -Operation Offboard -Config $config)
    if ($Provider -eq 'ActiveDirectory') { Assert-ActiveDirectoryAvailable }
    else { $state = Get-IamMockState -StatePath $StatePath }
    $changed = $false
    foreach ($row in $rows) {
        $sam = $row.samAccountName
        if ($Provider -eq 'Mock') {
            $matches = @(Find-MockUser -State $state -Sam $sam -EmployeeId $row.employeeId)
            if ($matches.Count -gt 1) { throw "Ambiguous ID/username collision for $sam." }
            $user = if ($matches.Count -eq 1) { $matches[0] } else { $null }
        }
        else { $user = Find-AdLabUser -Sam $sam -Config $config }
        if ($null -eq $user) {
            [pscustomobject]@{ EmployeeId = $row.employeeId; SamAccountName = $sam; Status = 'NotFound'; Detail = 'No action taken' }
            continue
        }
        if ($user.employeeId -ne $row.employeeId) {
            throw "Identity mismatch for '$sam': CSV ID $($row.employeeId) does not match directory ID $($user.employeeId)."
        }
        $managedMemberships = @()
        if ($Provider -eq 'Mock') {
            $managedMemberships = @($user.groups | Where-Object { @($config.managedGroups) -contains $_ })
        }
        else {
            $membership = @(Get-ADPrincipalGroupMembership -Identity $user.DistinguishedName -ErrorAction Stop)
            $managedMemberships = @($membership | Where-Object { @($config.managedGroups) -contains $_.Name } | ForEach-Object { $_.Name })
        }
        if (-not $user.Enabled -and $managedMemberships.Count -eq 0) {
            [pscustomobject]@{ EmployeeId = $row.employeeId; SamAccountName = $sam; Status = 'AlreadyOffboarded'; Detail = 'No changes made' }
            continue
        }
        if (-not $Execute) {
            [pscustomobject]@{ EmployeeId = $row.employeeId; SamAccountName = $sam; Status = 'Planned'; Detail = 'Disable account and remove only managed group memberships' }
            continue
        }
        if (-not $PSCmdlet.ShouldProcess($sam, 'Disable lab account and remove managed groups')) {
            [pscustomobject]@{ EmployeeId = $row.employeeId; SamAccountName = $sam; Status = 'Skipped'; Detail = 'WhatIf or confirmation declined' }
            continue
        }
        if ($Provider -eq 'Mock') {
            $user.enabled = $false
            $user.groups = @($user.groups | Where-Object { @($config.managedGroups) -notcontains $_ })
            $user.disabledAtUtc = [DateTime]::UtcNow.ToString('o')
            $user.lifecycleStatus = 'Offboarded'
            $changed = $true
        }
        else {
            Disable-ADAccount -Identity $user.DistinguishedName -ErrorAction Stop
            Set-ADUser -Identity $user.DistinguishedName -Description 'IAMLAB:Offboarded' -ErrorAction Stop
            foreach ($group in $managedMemberships) {
                Remove-ADGroupMember -Identity $group -Members $user.DistinguishedName -Confirm:$false -ErrorAction Stop
            }
        }
        [pscustomobject]@{ EmployeeId = $row.employeeId; SamAccountName = $sam; Status = 'Offboarded'; Detail = "Removed $($managedMemberships.Count) managed group memberships" }
    }
    if ($Provider -eq 'Mock' -and $changed) { Save-IamMockState -State $state -StatePath $StatePath }
}

function Invoke-IamActivate {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$CsvPath,
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$StatePath,
        [ValidateSet('Mock', 'ActiveDirectory')][string]$Provider = 'Mock',
        [switch]$Execute,
        [Security.SecureString]$InitialPassword
    )
    $config = Get-IamConfiguration -ConfigPath $ConfigPath
    $rows = @(Read-IamCsv -CsvPath $CsvPath -Operation Offboard -Config $config)
    if ($Provider -eq 'ActiveDirectory') {
        Assert-ActiveDirectoryAvailable
        if ($Execute -and $null -eq $InitialPassword) { throw 'ActiveDirectory activation requires a SecureString -InitialPassword; never store it in a file or source control.' }
    }
    else { $state = Get-IamMockState -StatePath $StatePath }
    $changed = $false
    foreach ($row in $rows) {
        $sam = $row.samAccountName
        if ($Provider -eq 'Mock') {
            $matches = @(Find-MockUser -State $state -Sam $sam -EmployeeId $row.employeeId)
            if ($matches.Count -gt 1) { throw "Ambiguous ID/username collision for $sam." }
            $user = if ($matches.Count -eq 1) { $matches[0] } else { $null }
        }
        else { $user = Find-AdLabUser -Sam $sam -Config $config }
        if ($null -eq $user) {
            [pscustomobject]@{ EmployeeId = $row.employeeId; SamAccountName = $sam; Status = 'NotFound'; Detail = 'No action taken' }
            continue
        }
        if ($user.employeeId -ne $row.employeeId) { throw "Identity mismatch for '$sam'." }
        if ($user.Enabled) {
            [pscustomobject]@{ EmployeeId = $row.employeeId; SamAccountName = $sam; Status = 'AlreadyEnabled'; Detail = 'No changes made' }
            continue
        }
        $isPending = if ($Provider -eq 'Mock') { $user.lifecycleStatus -eq 'PendingActivation' } else { $user.Description -eq 'IAMLAB:PendingActivation' }
        if (-not $isPending) {
            [pscustomobject]@{ EmployeeId = $row.employeeId; SamAccountName = $sam; Status = 'Blocked'; Detail = 'Only pending-activation users may be enabled' }
            continue
        }
        if (-not $Execute) {
            [pscustomobject]@{ EmployeeId = $row.employeeId; SamAccountName = $sam; Status = 'Planned'; Detail = 'Activate pending user after credential approval' }
            continue
        }
        if (-not $PSCmdlet.ShouldProcess($sam, 'Activate lab user after credential approval')) {
            [pscustomobject]@{ EmployeeId = $row.employeeId; SamAccountName = $sam; Status = 'Skipped'; Detail = 'WhatIf or confirmation declined' }
            continue
        }
        if ($Provider -eq 'Mock') {
            $user.enabled = $true
            $user.lifecycleStatus = 'Active'
            $changed = $true
        }
        else {
            Set-ADAccountPassword -Identity $user.DistinguishedName -Reset -NewPassword $InitialPassword -ErrorAction Stop
            Set-ADUser -Identity $user.DistinguishedName -ChangePasswordAtLogon $true -Description 'IAMLAB:Active' -ErrorAction Stop
            Enable-ADAccount -Identity $user.DistinguishedName -ErrorAction Stop
        }
        [pscustomobject]@{ EmployeeId = $row.employeeId; SamAccountName = $sam; Status = 'Activated'; Detail = 'User enabled' }
    }
    if ($Provider -eq 'Mock' -and $changed) { Save-IamMockState -State $state -StatePath $StatePath }
}

function Get-IamAccessAudit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$StatePath,
        [ValidateSet('Mock', 'ActiveDirectory')][string]$Provider = 'Mock'
    )
    $config = Get-IamConfiguration -ConfigPath $ConfigPath
    if ($Provider -eq 'Mock') { $users = @( (Get-IamMockState -StatePath $StatePath).users ) }
    else {
        Assert-ActiveDirectoryAvailable
        $users = @(Get-ADUser -Filter * -SearchBase $config.organizationalUnit -Properties Department, EmployeeID, MemberOf, Description -ErrorAction Stop |
            ForEach-Object {
                $u = $_
                [pscustomobject]@{
                    employeeId = $u.EmployeeID; samAccountName = $u.SamAccountName
                    department = $u.Department; enabled = $u.Enabled
                    lifecycleStatus = $(if ($u.Description -eq 'IAMLAB:PendingActivation') { 'PendingActivation' } else { 'Other' })
                    groups = @(Get-ADPrincipalGroupMembership -Identity $u.DistinguishedName -ErrorAction Stop | ForEach-Object { $_.Name })
                }
            })
    }
    foreach ($user in $users) {
        $findings = @()
        $dept = [string]$user.department
        $mapped = $config.groupsByDepartment.PSObject.Properties[$dept]
        $expected = @()
        if ($null -eq $mapped) {
            $findings += [pscustomobject]@{ Finding = 'UnknownDepartment'; Severity = 'High'; Group = '' }
        }
        else { $expected = @(Get-ManagedGroupsForDepartment -Config $config -Department $dept) }
        $actualManaged = @($user.groups | Where-Object { @($config.managedGroups) -contains $_ })
        $isPending = ($null -ne $user.PSObject.Properties['lifecycleStatus'] -and $user.lifecycleStatus -eq 'PendingActivation')
        if (-not $user.enabled -and $isPending) {
            $findings += [pscustomobject]@{ Finding = 'PendingActivation'; Severity = 'Info'; Group = '' }
        }
        if ($user.enabled) {
            foreach ($missing in $expected) {
                if ($actualManaged -notcontains $missing) {
                    $findings += [pscustomobject]@{ Finding = 'MissingExpectedGroup'; Severity = 'Medium'; Group = $missing }
                }
            }
        }
        foreach ($group in $actualManaged) {
            if (-not $user.enabled -and -not $isPending) {
                $findings += [pscustomobject]@{ Finding = 'DisabledUserHasManagedAccess'; Severity = 'High'; Group = $group }
            }
            elseif ($expected -notcontains $group) {
                $findings += [pscustomobject]@{ Finding = 'UnexpectedManagedGroup'; Severity = 'High'; Group = $group }
            }
        }
        if ($findings.Count -eq 0) { $findings = @([pscustomobject]@{ Finding = 'Compliant'; Severity = 'Info'; Group = '' }) }
        foreach ($finding in $findings) {
            [pscustomobject]@{
                EmployeeId = $user.employeeId
                SamAccountName = $user.samAccountName
                Department = $dept
                Enabled = [bool]$user.enabled
                Group = $finding.Group
                Finding = $finding.Finding
                Severity = $finding.Severity
            }
        }
    }
}

Export-ModuleMember -Function Initialize-IamMockState, Invoke-IamOnboard, Invoke-IamActivate, Invoke-IamOffboard, Get-IamAccessAudit, Get-IamConfiguration
