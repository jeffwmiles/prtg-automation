# This script will create the required Disaster Recovery health sensor in PRTG.
# This requires the file "azureasrhealth.template" from source control is placed on the PRTG Probe in this location:
# - C:\Program Files (x86)\PRTG Network Monitor\Custom Sensors\rest

# Input Variables - update accordingly
$ClientCode = "abc"
$resourcegroupname = "$($clientcode)-srv-rg" # resource group where the Application Gateway is located
$appgwname = "$clientcode AppGw" # name of the application gateway
$httpsettingname = @("Test","Prod")
$probename = "Probe1"
$subscriptionid = "549d4d62" # Client Azure subscription

$appsvcname = "AppGw Monitor"
$appsvcFQDN = "prod-appsvc.azurewebsites.net"
$functionName = "Get-AppGw-Health"
$functionKey = "secret function key for PRTG"
$tenantid = "f5f7b07a" # Azure tenant id

# No edits need to be made below this line
## ----------------- ##

# PrtgAPI is being used: https://github.com/lordmilko/PrtgAPI

#Check if module is installed, and install it if not
$moduleinstalled = get-module prtgapi -listavailable
if ($moduleinstalled) {
    Write-Host "Pre-requisite Module is installed, will continue"
}
else {
    Install-Package PrtgAPI -Source PSGallery -Force
    Write-Host "Installing PrtgApi from the PSGallery"
}

# Check and see if we're already connected to PRTG Core
$prtgconnection = Get-PrtgClient
if (!$prtgconnection) {
    # If not, make the connection
    Write-Host "You will now be prompted for your PRTG credentials"
    Connect-PrtgServer prtgserver.domain.com
}

Write-Host "Connected to PRTG. Proceeding with setup."

# Using our defined group structure, check for the device existence
$device = Get-Probe $probename | Get-Group "Services" | Get-Group "Application Gateways" | Get-Device $appsvcname

# httpsetting variable is an array, iterate through it, and perform sensor creation for each item
foreach ($setting in $httpsettingname) {

# Define the POST body that will be supplied to the Azure Function    
$Body = @"
{
    "httpsettingname": "$setting",
    "resourcegroupname": "$resourcegroupname",
    "appgwname": "$appgwname",
    "subscriptionid": "$subscriptionid",
    "tenantid": "$tenantid"
}
"@
    
    if ($device) {
        write-host "found device, checking for sensor"
        # Assume our sensor is created with this naming convention
        $sensor = $device | get-sensor "$($appgwname) $($setting)"
        if ($sensor) {
            Write-Host "Sensor already exists for this client"
        }
        else {
            Write-Host "Sensor not found, proceeding with creation"
            # Gather a default set of parameters for the type of sensor that we want to create
            $params = Get-Device $device | New-SensorParameters -RawType restcustom | Select-object -First 1 # selecting first because PrtgApi seems to find multiple devices with same name
            # For some reason, above command creates two objects in Params, so we only target the first one by getting -First 1
            
            # Populate the sensor parameters with our desired values
            $params.query = "/api/$($functionName)?code=$functionKey"
            $params.jsonfile = "azureappgwhealth.template" # use the standard template that was built
            $params.protocol = 1 # sets as HTTPS
            $params.requestbody = $body
            $params.Interval = "00:5:00" # 5 minute interval, deviates from the default
            $params.requesttype = 1 # this makes it a POST instead of GET
            if ($setting -like "*prod*") {
                # Set some Tags on the sensor
                $params.Tags = @("restcustomsensor", "restsensor", "Tier2", "$($ClientCode.toUpper())", "ApplicationGateway", "PRTGMaintenance", "Production")
            }
            else {
                # Assume Test if not prod, set a different set of Tags
                $params.Tags = @("restcustomsensor", "restsensor", "Tier2", "$($ClientCode.toUpper())", "ApplicationGateway", "PRTGMaintenance", "NonProduction")
            }
            $params.Name = "$($appgwname) $($setting)"
            $sensor = $device | Add-Sensor $params # Create the sensor

            # Set the Schedule to allow our PRTG Maintenance Window to function properly
            # Since we're setting maintenance windows from the PRTG API, the sensor/group must have a defined schedule, not inheriting
            Set-ObjectProperty -object $sensor -RawParameters @{
                "scheduledependency" = 0
                "schedule_"          = Get-PrtgSchedule "24x7 (Used to disable Schedule Inheritance)"
            } -force

        }
    }
    else {
        write-host "no device found, creating it..."
        $device = Get-Probe $probename | Get-Group "Services" | Get-Group "Application Gateways" | Add-Device $appsvcname -Host $appsvcFQDN
        Write-Host "Proceeding with sensor creation"
        # Gather a default set of parameters for the type of sensor that we want to create
            $params = Get-Device $device | New-SensorParameters -RawType restcustom | Select-object -First 1 # selecting first because PrtgApi seems to find multiple devices with same name
            # For some reason, above command creates two objects in Params, so we only target the first one by getting -First 1
            
            # Populate the sensor parameters with our desired values
            $params.query = "/api/$($functionName)?code=$functionKey"
            $params.jsonfile = "azureappgwhealth.template" # use the standard template that was built
            $params.protocol = 1 # sets as HTTPS
            $params.requestbody = $body
            $params.Interval = "00:5:00" # 5 minute interval, deviates from the default
            $params.requesttype = 1 # this makes it a POST instead of GET
            if ($setting -like "*prod*") {
                # Set some Tags on the sensor
                $params.Tags = @("restcustomsensor", "restsensor", "Tier2", "$($ClientCode.toUpper())", "ApplicationGateway", "PRTGMaintenance", "Production")
            }
            else {
                # Assume Test if not prod, set a different set of Tags
                $params.Tags = @("restcustomsensor", "restsensor", "Tier2", "$($ClientCode.toUpper())", "ApplicationGateway", "PRTGMaintenance", "NonProduction")
            }
            $params.Name = "$($appgwname) $($setting)"
            $sensor = $device | Add-Sensor $params # Create the sensor

            # Set the Schedule to allow our PRTG Maintenance Window to function properly
            # Since we're setting maintenance windows from the PRTG API, the sensor/group must have a defined schedule, not inheriting
            Set-ObjectProperty -object $sensor -RawParameters @{
                "scheduledependency" = 0
                "schedule_"          = Get-PrtgSchedule "24x7 (Used to disable Schedule Inheritance)"
            } -force
    }
}
