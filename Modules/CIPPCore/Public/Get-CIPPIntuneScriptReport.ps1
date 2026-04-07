function Get-CIPPIntuneScriptReport {
    <#
    .SYNOPSIS
        Returns Intune scripts from the CIPP reporting database

    .DESCRIPTION
        Retrieves cached script data for all script types (Windows, MacOS, Remediation, Linux),
        applying the same assignment resolution and scriptType enrichment as the live
        Invoke-ListIntuneScript endpoint.

    .PARAMETER TenantFilter
        Tenant domain name or 'AllTenants'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    if ($TenantFilter -eq 'AllTenants') {
        $AnyItems = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'IntuneScriptsWindows'
        $Tenants = @(
            $AnyItems |
                Where-Object { $_.RowKey -notlike '*-Count' } |
                Select-Object -ExpandProperty PartitionKey -Unique
        )

        $TenantList = Get-Tenants -IncludeErrors
        $Tenants = $Tenants | Where-Object { $TenantList.defaultDomainName -contains $_ }

        $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Tenant in $Tenants) {
            try {
                $TenantResults = Get-CIPPIntuneScriptReport -TenantFilter $Tenant
                foreach ($Result in $TenantResults) {
                    $Result | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
                    $AllResults.Add($Result)
                }
            } catch {
                Write-LogMessage -API 'IntuneScriptReport' -tenant $Tenant `
                    -message "Failed to get report: $($_.Exception.Message)" -sev Warning
            }
        }
        return $AllResults
    }

    # Load cached groups for assignment resolution
    $GroupItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Groups' |
        Where-Object { $_.RowKey -notlike '*-Count' }

    $Groups = foreach ($GroupItem in $GroupItems) {
        try { $GroupItem.Data | ConvertFrom-Json -ErrorAction Stop } catch { $null }
    }

    $CacheTimestamp = $null
    $Results = [System.Collections.Generic.List[System.Object]]::new()

    # Script type map: DB type key -> scriptType label
    $ScriptTypes = @(
        @{ Type = 'IntuneScriptsWindows'; ScriptType = 'Windows' }
        @{ Type = 'IntuneScriptsMacOS'; ScriptType = 'MacOS' }
        @{ Type = 'IntuneScriptsRemediation'; ScriptType = 'Remediation' }
        @{ Type = 'IntuneScriptsLinux'; ScriptType = 'Linux' }
    )

    foreach ($ScriptTypeDef in $ScriptTypes) {
        $Items = Get-CIPPDbItem -TenantFilter $TenantFilter -Type $ScriptTypeDef.Type |
            Where-Object { $_.RowKey -notlike '*-Count' }

        if (-not $Items) { continue }

        $TypeTimestamp = ($Items | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp
        if ($null -eq $CacheTimestamp -or ($TypeTimestamp -and $TypeTimestamp -gt $CacheTimestamp)) {
            $CacheTimestamp = $TypeTimestamp
        }

        foreach ($Item in $Items) {
            $script = try { $Item.Data | ConvertFrom-Json -Depth 10 -ErrorAction Stop } catch { continue }
            if ($null -eq $script) { continue }

            # Linux scripts use 'name' instead of 'displayName'
            if ($ScriptTypeDef.ScriptType -eq 'Linux') {
                if ($null -eq $script.displayName -and $script.name) {
                    $script | Add-Member -NotePropertyName displayName -NotePropertyValue $script.name -Force
                }
            }

            # Resolve assignments — identical to live endpoint
            $ScriptAssignment = [System.Collections.Generic.List[string]]::new()
            $ScriptExclude = [System.Collections.Generic.List[string]]::new()

            if ($script.assignments) {
                foreach ($Assignment in $script.assignments) {
                    $target = $Assignment.target
                    switch ($target.'@odata.type') {
                        '#microsoft.graph.allDevicesAssignmentTarget' { $ScriptAssignment.Add('All Devices') }
                        '#microsoft.graph.allLicensedUsersAssignmentTarget' { $ScriptAssignment.Add('All Licensed Users') }
                        '#microsoft.graph.groupAssignmentTarget' {
                            $groupName = ($Groups | Where-Object { $_.id -eq $target.groupId }).displayName
                            if ($groupName) { $ScriptAssignment.Add($groupName) }
                        }
                        '#microsoft.graph.exclusionGroupAssignmentTarget' {
                            $groupName = ($Groups | Where-Object { $_.id -eq $target.groupId }).displayName
                            if ($groupName) { $ScriptExclude.Add($groupName) }
                        }
                    }
                }
            }

            $script | Add-Member -NotePropertyName 'scriptType' -NotePropertyValue $ScriptTypeDef.ScriptType -Force
            $script | Add-Member -NotePropertyName 'ScriptAssignment' -NotePropertyValue ($ScriptAssignment -join ', ') -Force
            $script | Add-Member -NotePropertyName 'ScriptExclude' -NotePropertyValue ($ScriptExclude -join ', ') -Force
            $script | Add-Member -NotePropertyName CacheTimestamp -NotePropertyValue $CacheTimestamp -Force

            $Results.Add($script)
        }
    }

    if ($Results.Count -eq 0) {
        throw "No cached data found for $TenantFilter. Run a cache sync first."
    }

    return $Results
}
