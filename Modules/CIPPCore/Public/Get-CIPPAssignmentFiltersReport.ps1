function Get-CIPPAssignmentFiltersReport {
    <#
    .SYNOPSIS
        Returns assignment filters from the CIPP reporting database

    .PARAMETER TenantFilter
        Tenant domain name or 'AllTenants'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    if ($TenantFilter -eq 'AllTenants') {
        $AnyItems = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'AssignmentFilters'
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
                $TenantResults = Get-CIPPAssignmentFiltersReport -TenantFilter $Tenant
                foreach ($Result in $TenantResults) {
                    $Result | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
                    $AllResults.Add($Result)
                }
            } catch {
                Write-LogMessage -API 'AssignmentFiltersReport' -tenant $Tenant `
                    -message "Failed to get report: $($_.Exception.Message)" -sev Warning
            }
        }
        return $AllResults
    }

    $Items = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'AssignmentFilters' |
        Where-Object { $_.RowKey -notlike '*-Count' }

    if (-not $Items) {
        throw "No cached data found for $TenantFilter. Run a cache sync first."
    }

    $CacheTimestamp = (
        $Items |
            Where-Object { $_.Timestamp } |
            Sort-Object Timestamp -Descending |
            Select-Object -First 1
    ).Timestamp

    $Results = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($Item in $Items) {
        $Obj = try {
            $Item.Data | ConvertFrom-Json -Depth 10 -ErrorAction Stop
        } catch { continue }

        if ($null -eq $Obj) { continue }

        # No enrichment needed — live endpoint returns raw Graph data
        $Obj | Add-Member -NotePropertyName CacheTimestamp -NotePropertyValue $CacheTimestamp -Force
        $Results.Add($Obj)
    }

    return $Results
}
