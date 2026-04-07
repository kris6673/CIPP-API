function Get-CIPPAppProtectionPoliciesReport {
    <#
    .SYNOPSIS
        Returns app protection & configuration policies from the CIPP reporting database

    .DESCRIPTION
        Retrieves cached app protection policy data, applying the same assignment resolution
        and PolicyTypeName enrichment as the live Invoke-ListAppProtectionPolicies endpoint.
        Uses data from both IntuneAppProtectionPolicies (managed app policies without expanded
        assignments) and IntuneIosAppProtectionPolicies / IntuneAndroidAppProtectionPolicies
        (which have assignments expanded).

    .PARAMETER TenantFilter
        Tenant domain name or 'AllTenants'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    if ($TenantFilter -eq 'AllTenants') {
        $AnyItems = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'IntuneIosAppProtectionPolicies'
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
                $TenantResults = Get-CIPPAppProtectionPoliciesReport -TenantFilter $Tenant
                foreach ($Result in $TenantResults) {
                    $Result | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
                    $AllResults.Add($Result)
                }
            } catch {
                Write-LogMessage -API 'AppProtectionPoliciesReport' -tenant $Tenant `
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
    $GraphRequest = [System.Collections.Generic.List[object]]::new()

    # Map of DB types to their URLName values used by the live endpoint
    $PolicySources = @(
        @{ Type = 'IntuneIosAppProtectionPolicies'; URLName = 'iosManagedAppProtection' }
        @{ Type = 'IntuneAndroidAppProtectionPolicies'; URLName = 'androidManagedAppProtection' }
        @{ Type = 'IntuneMobileAppConfigurations'; URLName = 'mobileAppConfigurations'; Source = 'AppConfiguration' }
    )

    foreach ($Source in $PolicySources) {
        $Items = Get-CIPPDbItem -TenantFilter $TenantFilter -Type $Source.Type |
            Where-Object { $_.RowKey -notlike '*-Count' }

        if (-not $Items) { continue }

        $TypeTimestamp = ($Items | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp
        if ($null -eq $CacheTimestamp -or ($TypeTimestamp -and $TypeTimestamp -gt $CacheTimestamp)) {
            $CacheTimestamp = $TypeTimestamp
        }

        foreach ($Item in $Items) {
            $Policy = try { $Item.Data | ConvertFrom-Json -Depth 10 -ErrorAction Stop } catch { continue }
            if ($null -eq $Policy) { continue }

            # Determine PolicyTypeName — identical logic to the live endpoint
            if ($Source.Source -eq 'AppConfiguration') {
                $policyType = switch -Wildcard ($Policy.'@odata.type') {
                    '*androidManagedStoreAppConfiguration*' { 'Android Enterprise App Configuration' }
                    '*androidForWorkAppConfigurationSchema*' { 'Android for Work Configuration' }
                    '*iosMobileAppConfiguration*' { 'iOS App Configuration' }
                    default { 'App Configuration Policy' }
                }
                $PolicySourceValue = 'AppConfiguration'
            } else {
                $policyType = switch ($Source.URLName) {
                    'androidManagedAppProtection' { 'Android App Protection' }
                    'iosManagedAppProtection' { 'iOS App Protection' }
                    'windowsManagedAppProtection' { 'Windows App Protection' }
                    'mdmWindowsInformationProtectionPolicy' { 'Windows Information Protection (MDM)' }
                    'targetedManagedAppConfiguration' { 'App Configuration (MAM)' }
                    default { 'App Protection Policy' }
                }
                $PolicySourceValue = 'AppProtection'
            }

            # Resolve assignments
            $PolicyAssignment = [System.Collections.Generic.List[string]]::new()
            $PolicyExclude = [System.Collections.Generic.List[string]]::new()

            if ($Policy.assignments) {
                foreach ($Assignment in $Policy.assignments) {
                    $target = $Assignment.target
                    switch ($target.'@odata.type') {
                        '#microsoft.graph.allDevicesAssignmentTarget' { $PolicyAssignment.Add('All Devices') }
                        '#microsoft.graph.allLicensedUsersAssignmentTarget' { $PolicyAssignment.Add('All Licensed Users') }
                        '#microsoft.graph.groupAssignmentTarget' {
                            $groupName = ($Groups | Where-Object { $_.id -eq $target.groupId }).displayName
                            if ($groupName) { $PolicyAssignment.Add($groupName) }
                        }
                        '#microsoft.graph.exclusionGroupAssignmentTarget' {
                            $groupName = ($Groups | Where-Object { $_.id -eq $target.groupId }).displayName
                            if ($groupName) { $PolicyExclude.Add($groupName) }
                        }
                    }
                }
            }

            $Policy | Add-Member -NotePropertyName 'PolicyTypeName' -NotePropertyValue $policyType -Force
            $Policy | Add-Member -NotePropertyName 'URLName' -NotePropertyValue $Source.URLName -Force
            $Policy | Add-Member -NotePropertyName 'PolicySource' -NotePropertyValue $PolicySourceValue -Force
            $Policy | Add-Member -NotePropertyName 'PolicyAssignment' -NotePropertyValue ($PolicyAssignment -join ', ') -Force
            $Policy | Add-Member -NotePropertyName 'PolicyExclude' -NotePropertyValue ($PolicyExclude -join ', ') -Force
            $Policy | Add-Member -NotePropertyName CacheTimestamp -NotePropertyValue $CacheTimestamp -Force

            $GraphRequest.Add($Policy)
        }
    }

    if ($GraphRequest.Count -eq 0) {
        throw "No cached data found for $TenantFilter. Run a cache sync first."
    }

    return ($GraphRequest | Sort-Object -Property displayName)
}
