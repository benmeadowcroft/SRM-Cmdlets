
<#
.SYNOPSIS
Trigger Discover Devices for Site Recovery Manager

.PARAMETER ProtectionGroup
Return discover devices task
#>
Function Start-DiscoverDevices {
    $api = Get-ServerApiEndpoint
    [VMware.VimAutomation.Srm.Views.DiscoverDevicesTask] $task = $api.Storage.DiscoverDevices()

    return $task
}
