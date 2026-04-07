function Set-CIPPDBCacheAssignmentFilters {
    <#
    .SYNOPSIS
        Caches Intune assignment filters for a tenant

    .PARAMETER TenantFilter
        The tenant to cache assignment filters for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching assignment filters' -sev Debug

        $Data = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/assignmentFilters' -tenantid $TenantFilter
        if (!$Data) { $Data = @() }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'AssignmentFilters' -Data @($Data)
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'AssignmentFilters' -Data @($Data) -Count

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Cached $(($Data | Measure-Object).Count) assignment filters" -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Failed to cache assignment filters: $($_.Exception.Message)" -sev Error `
            -LogData (Get-CippException -Exception $_)
    }
}
