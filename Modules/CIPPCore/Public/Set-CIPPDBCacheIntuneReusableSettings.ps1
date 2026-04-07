function Set-CIPPDBCacheIntuneReusableSettings {
    <#
    .SYNOPSIS
        Caches Intune reusable policy settings for a tenant

    .PARAMETER TenantFilter
        The tenant to cache reusable settings for

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
        $TestResult = Test-CIPPStandardLicense -StandardName 'IntuneReusableSettingsCache' -TenantFilter $TenantFilter -RequiredCapabilities @('INTUNE_A', 'MDM_Services', 'EMS', 'SCCM', 'MICROSOFTINTUNEPLAN1') -SkipLog

        if ($TestResult -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have Intune license, skipping reusable settings cache' -sev Debug
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Intune reusable settings' -sev Debug

        $selectFields = @(
            'id'
            'settingInstance'
            'displayName'
            'description'
            'settingDefinitionId'
            'version'
            'referencingConfigurationPolicyCount'
            'createdDateTime'
            'lastModifiedDateTime'
        )
        $selectQuery = '?$select=' + ($selectFields -join ',')
        $uri = "https://graph.microsoft.com/beta/deviceManagement/reusablePolicySettings$selectQuery"

        $Data = New-GraphGetRequest -uri $uri -tenantid $TenantFilter
        if (!$Data) { $Data = @() }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneReusableSettings' -Data @($Data)
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneReusableSettings' -Data @($Data) -Count

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Cached $(($Data | Measure-Object).Count) reusable settings" -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Failed to cache reusable settings: $($_.Exception.Message)" -sev Error `
            -LogData (Get-CippException -Exception $_)
    }
}
