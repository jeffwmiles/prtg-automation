#This Azure Function is used to get replication health status for a specified DR fabric
# Calling the Function manually:
<#
    $appsvcname = "appsvc.azurewebsites.net"
    $functionName = "Get-AppGw-Health"
    $functionKey = "< insert key here >"
    $Body = @"
{
    "httpsettingname": "< prodint >",
    "resourcegroupname": "< int or ext >",
    "appgwname": "< int or ext >",
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
$httpsettingname = $Request.Query.httpsettingname
if (-not $httpsettingname) {
    $httpsettingname = $Request.Body.httpsettingname
}
$appgwname = $Request.Query.appgwname
if (-not $appgwname) {
    $appgwname = $Request.Body.appgwname
}
$resourcegroupname = $Request.Query.resourcegroupname
if (-not $resourcegroupname) {
    $resourcegroupname = $Request.Body.resourcegroupname
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
if ($appgwname -and $httpsettingname -and $resourcegroupname -and $subscriptionid -and $tenantid) {
    $status = [HttpStatusCode]::OK
    # Make sure we're using the right Subscription
    Select-AzSubscription -SubscriptionID $subscriptionid -TenantID $tenantid
    # Get the health status, using the Expanded Resource parameter
    $healthexpand = Get-AzApplicationGatewayBackendHealth -Name $appgwname -ResourceGroupName $resourcegroupname -ExpandResource "backendhealth/applicationgatewayresource"
    # If serving multiple sites out of one AppGw, use the parameter $httpsettingname to filter so we can better organize in PRTG
    $filtered = $healthexpand.BackEndAddressPools.BackEndhttpsettingscollection | where-object { $_.Backendhttpsettings.Name -eq "$($httpsettingname)-httpsetting" }
    # Return results as boolean integers, either health or not. Could modify this to be additional values if desired
    $items = $filtered.Servers | select-object Address, @{Name = 'Health'; Expression = { if ($_.Health -eq "Healthy") { 1 } else { 0 } } }
    # Add a top-level property so that the PRTG custom sensor template can interpret the results properly
    $body = @{ items = $items }
}
else {
    $status = [HttpStatusCode]::BadRequest
    $body = "Bad Request - Check logs for details."
    Write-Output "Request failed:"
    Write-Output "Fields consumed as follows: `n httpsettingname: $($httpsettingname) `n appgwname: $($appgwname) `n resourcegroupname: $($resourcegroupname) `n subscriptionid: $($subscriptionid) `n tenantid: $($tenantid)"
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $status
        Body       = $body
    })