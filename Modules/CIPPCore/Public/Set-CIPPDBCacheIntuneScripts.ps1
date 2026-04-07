function Set-CIPPDBCacheIntuneScripts {
    <#
    .SYNOPSIS
        Caches all Intune script types for a tenant

    .DESCRIPTION
        Fetches Windows, MacOS, Remediation, and Linux scripts (with assignments)
        and stores each type separately in the reporting database.

    .PARAMETER TenantFilter
        The tenant to cache scripts for

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
        $TestResult = Test-CIPPStandardLicense -StandardName 'IntuneScriptsCache' -TenantFilter $TenantFilter -RequiredCapabilities @('INTUNE_A', 'MDM_Services', 'EMS', 'SCCM', 'MICROSOFTINTUNEPLAN1') -SkipLog

        if ($TestResult -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have Intune license, skipping scripts cache' -sev Debug
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Intune scripts' -sev Debug

        $BulkRequests = @(
            @{
                id     = 'Windows'
                method = 'GET'
                url    = '/deviceManagement/deviceManagementScripts?$expand=assignments'
            }
            @{
                id     = 'MacOS'
                method = 'GET'
                url    = '/deviceManagement/deviceShellScripts?$expand=assignments'
            }
            @{
                id     = 'Remediation'
                method = 'GET'
                url    = '/deviceManagement/deviceHealthScripts?$expand=assignments'
            }
            @{
                id     = 'Linux'
                method = 'GET'
                url    = '/deviceManagement/configurationPolicies?$expand=assignments'
            }
        )

        $BulkResults = New-GraphBulkRequest -Requests @($BulkRequests) -tenantid $TenantFilter

        foreach ($scriptType in @('Windows', 'MacOS', 'Remediation', 'Linux')) {
            $BulkResult = $BulkResults | Where-Object { $_.id -eq $scriptType }
            if ($BulkResult.status -ne 200) {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to fetch $scriptType scripts: $($BulkResult.body.error.message)" -sev Warning
                continue
            }

            $scripts = $BulkResult.body.value

            # Linux scripts need filtering — same logic as live endpoint
            if ($scriptType -eq 'Linux') {
                $scripts = @($scripts | Where-Object { $_.platforms -eq 'linux' -and $_.templateReference.templateFamily -eq 'deviceConfigurationScripts' })
            }

            $DbType = "IntuneScripts$scriptType"
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type $DbType -Data @($scripts)
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type $DbType -Data @($scripts) -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $(($scripts | Measure-Object).Count) $scriptType scripts" -sev Debug
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Intune scripts successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Failed to cache Intune scripts: $($_.Exception.Message)" -sev Error `
            -LogData (Get-CippException -Exception $_)
    }
}
