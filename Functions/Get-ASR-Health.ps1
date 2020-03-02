#This Azure Function is used to get replication health status for a specified DR fabric
# Calling the Function manually:
<#
    $appsvcname = "appsvc.azurewebsites.net"
    $functionName = "Get-ASR-Health"
    $functionKey = "< insert key here >"
    $Body = @"
{
	"clientcode": "client",
	"sourceregion": "eastus2",
	"subscriptionid": "< subid >",
	"tenantid": "< tenant id >"
}
"@
    $URI = "https://$($appsvcname)/api/$($functionName)?code=$functionKey"
    Invoke-RestMethod -Uri $URI -Method Post -body $body -ContentType "application/json"
#>
using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$ErrorActionPreference = "Stop"
# Write to the Azure Functions log stream.
Write-Output "PowerShell HTTP trigger function processed the following request."
Write-Output "$($Request.Body)"

# Interact with query parameters or the body of the request.
$clientcode = $Request.Query.clientcode
if (-not $clientcode) {
    $clientcode = $Request.Body.clientcode
}
$sourceregion = $Request.Query.sourceregion
if (-not $sourceregion) {
    $sourceregion = $Request.Body.sourceregion
}
$subscriptionid = $Request.Query.subscriptionid
if (-not $subscriptionid) {
    $subscriptionid = $Request.Body.subscriptionid
}
$tenantid = $Request.Query.tenantid
if (-not $tenantid) {
    $tenantid = $Request.Body.tenantid
}

#Proceed if all request body parameters are found
if ($clientcode -and $sourceregion -and $subscriptionid -and $tenantid) {
    $status = [HttpStatusCode]::OK
    Select-AzSubscription -SubscriptionID $subscriptionid -TenantID $tenantid
    $vault = Get-AzRecoveryServicesVault -Name "cc-$($clientcode)-dr-rsv"
    Set-AzRecoveryServicesAsrVaultContext -Vault $vault
    $fabric = Get-AzRecoveryServicesAsrFabric -Name "eastus2-fabric"#"$($sourceregion)-fabric"
    $container = Get-AzRecoveryServicesAsrProtectionContainer -fabric $fabric
    $items = Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $container | select-object FriendlyName, @{Name = 'ReplicationHealth'; Expression = { if ($_.ReplicationHealth -eq "Normal") { 1 } else { 0 } } } #ReplicationHealth
    $body = @{ items = $items }
    # This outputs a 1 if Normal, and a 0 if not normal. PRTG sensor will then alert.
}
else {
    $status = [HttpStatusCode]::BadRequest
    $body = "Bad Request - Check logs for details."
    Write-Output "Request failed:"
    Write-Output "Fields consumed as follows: `n clientcode: $($clientcode) `n sourceregion: $($sourceregion) `n subscriptionid: $($subscriptionid) `n tenantid: $($tenantid)"
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $status
        Body       = $body
    })
