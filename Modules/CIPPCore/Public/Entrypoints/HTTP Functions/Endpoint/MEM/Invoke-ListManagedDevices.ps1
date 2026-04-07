function Invoke-ListManagedDevices {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $TenantFilter = $Request.Query.tenantFilter
    $UseReportDB = $Request.Query.UseReportDB

    try {
        # Cache/AllTenants short-circuit
        if ($TenantFilter -eq 'AllTenants' -or $UseReportDB -eq 'true') {
            try {
                $GraphRequest = Get-CIPPManagedDevicesReport -TenantFilter $TenantFilter -ErrorAction Stop
                $StatusCode = [HttpStatusCode]::OK
            } catch {
                $StatusCode = [HttpStatusCode]::InternalServerError
                $GraphRequest = $_.Exception.Message
            }
            return ([HttpResponseContext]@{
                StatusCode = $StatusCode
                Body       = @($GraphRequest)
            })
        }

        # Live path — direct Graph call
        $GraphRequest = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/managedDevices?$top=999' -tenantid $TenantFilter
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to retrieve managed devices: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $GraphRequest = @()
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @($GraphRequest)
    })
}
