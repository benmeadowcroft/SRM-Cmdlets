# SRM Helper Methods - https://github.com/benmeadowcroft/SRM-Cmdlets

<#
.SYNOPSIS
Trigger Discover Devices for Site Recovery Manager

.OUTPUTS
Returns discover devices task
#>
Function Start-DiscoverDevices {
    [cmdletbinding()]
    Param(
        [VMware.VimAutomation.Srm.Types.V1.SrmServer] $SrmServer
    )

    $api = Get-ServerApiEndpoint -SrmServer $SrmServer

    [VMware.VimAutomation.Srm.Views.DiscoverDevicesTask] $task = $api.Storage.DiscoverDevices()

    return $task
}
