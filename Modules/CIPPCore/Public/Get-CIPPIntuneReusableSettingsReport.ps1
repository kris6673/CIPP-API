function Get-CIPPIntuneReusableSettingsReport {
    <#
    .SYNOPSIS
        Returns Intune reusable settings from the CIPP reporting database

    .PARAMETER TenantFilter
        Tenant domain name or 'AllTenants'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    if ($TenantFilter -eq 'AllTenants') {
        $AnyItems = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'IntuneReusableSettings'
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
                $TenantResults = Get-CIPPIntuneReusableSettingsReport -TenantFilter $Tenant
                foreach ($Result in $TenantResults) {
                    $Result | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
                    $AllResults.Add($Result)
                }
            } catch {
                Write-LogMessage -API 'IntuneReusableSettingsReport' -tenant $Tenant `
                    -message "Failed to get report: $($_.Exception.Message)" -sev Warning
            }
        }
        return $AllResults
    }

    $Items = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneReusableSettings' |
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

        # Re-apply RawJSON enrichment (same as live endpoint)
        $rawJson = $null
        try {
            $rawJson = $Obj | ConvertTo-Json -Depth 50 -Compress -ErrorAction Stop
        } catch {
            $rawJson = $null
        }
        $Obj | Add-Member -NotePropertyName 'RawJSON' -NotePropertyValue $rawJson -Force

        $Obj | Add-Member -NotePropertyName CacheTimestamp -NotePropertyValue $CacheTimestamp -Force
        $Results.Add($Obj)
    }

    return $Results
}
