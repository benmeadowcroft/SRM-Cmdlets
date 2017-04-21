
<#
.SYNOPSIS
Get the subset of recovery plans matching the input criteria

.PARAMETER Name
Return recovery plans matching the specified name

.PARAMETER ProtectionGroup
Return recovery plans associated with particular protection
groups
#>
Function Get-RecoveryPlan {
    [cmdletbinding()]
    Param(
        [Parameter(position=1)][string] $Name,
        [Parameter (ValueFromPipeline=$true)][VMware.VimAutomation.Srm.Views.SrmProtectionGroup[]] $ProtectionGroup,
        [VMware.VimAutomation.Srm.Types.V1.SrmServer] $SrmServer
    )

    begin {
        $api = Get-ServerApiEndpoint -SrmServer $SrmServer
        $rps = @()
    }
    process {
        if ($ProtectionGroup) {
            foreach ($pg in $ProtectionGroup) {
                $rps += $pg.ListRecoveryPlans()
            }
            $rps = Select_UniqueByMoRef($rps)
        } else {
            $rps += $api.Recovery.ListPlans()
        }
    }
    end {
        $rps | % {
            $rpi = $_.GetInfo()
            $selected = (-not $Name -or ($Name -eq $rpi.Name))
            if ($selected) {
                $_
            }
        }
    }
}

<#
.SYNOPSIS
Start a Recovery Plan action like test, recovery, cleanup, etc.

.PARAMETER RecoveryPlan
The recovery plan to start

.PARAMETER RecoveryMode
The recovery mode to invoke on the plan. May be one of "Test", "Cleanup", "Failover", "Reprotect"
#>
Function Start-RecoveryPlan {
    [cmdletbinding(SupportsShouldProcess=$True, ConfirmImpact="High")]
    Param(
        [Parameter (Mandatory=$true, ValueFromPipeline=$true, Position=1)][VMware.VimAutomation.Srm.Views.SrmRecoveryPlan] $RecoveryPlan,
        [VMware.VimAutomation.Srm.Views.SrmRecoveryPlanRecoveryMode] $RecoveryMode = [VMware.VimAutomation.Srm.Views.SrmRecoveryPlanRecoveryMode]::Test
    )

    # Validate with informative error messages
    $rpinfo = $RecoveryPlan.GetInfo()

    # Prompt the user to confirm they want to execute the action
    if ($pscmdlet.ShouldProcess($rpinfo.Name, $RecoveryMode)) {
        if ($rpinfo.State -eq 'Protecting') {
            throw "This recovery plan action needs to be initiated from the other SRM instance"
        }

        $RecoveryPlan.Start($RecoveryMode)
    }
}

<#
.SYNOPSIS
Stop a running Recovery Plan action.

.PARAMETER RecoveryPlan
The recovery plan to stop
#>
Function Stop-RecoveryPlan {
    [cmdletbinding(SupportsShouldProcess=$True,ConfirmImpact="High")]
    Param(
        [Parameter (Mandatory=$true, ValueFromPipeline=$true, Position=1)][VMware.VimAutomation.Srm.Views.SrmRecoveryPlan] $RecoveryPlan
    )

    # Validate with informative error messages
    $rpinfo = $RecoveryPlan.GetInfo()

    # Prompt the user to confirm they want to cancel the running action
    if ($pscmdlet.ShouldProcess($rpinfo.Name, 'Cancel')) {

        $RecoveryPlan.Cancel()
    }
}

<#
.SYNOPSIS
Retrieve the historical results of a recovery plan

.PARAMETER RecoveryPlan
The recovery plan to retrieve the history for
#>
Function Get-RecoveryPlanResult {
    [cmdletbinding()]
    Param(
        [Parameter (Mandatory=$true, ValueFromPipeline=$true, Position=1)][VMware.VimAutomation.Srm.Views.SrmRecoveryPlan] $RecoveryPlan,
        [VMware.VimAutomation.Srm.Views.SrmRecoveryPlanRecoveryMode] $RecoveryMode,
        [VMware.VimAutomation.Srm.Views.SrmRecoveryResultResultState] $ResultState,
        [DateTime] $StartedAfter,
        [DateTime] $startedBefore,
        [VMware.VimAutomation.Srm.Types.V1.SrmServer] $SrmServer
    )
    
    $api = Get-ServerApiEndpoint -SrmServer $SrmServer

    # Get the history objects
    $history = $api.Recovery.GetHistory($RecoveryPlan.MoRef)
    $resultCount = $history.GetResultCount()
    
    if ($resultCount -gt 0) {
        $results = $history.GetRecoveryResult($resultCount)

        $results |
            Where-Object { -not $RecoveryMode -or $_.RunMode -eq $RecoveryMode } |
            Where-Object { -not $ResultState -or $_.ResultState -eq $ResultState } |
            Where-Object { $null -eq $StartedAfter -or $_.StartTime -gt $StartedAfter } |
            Where-Object { $null -eq $StartedBefore -or $_.StartTime -lt $StartedBefore }
    }
}

<#
.SYNOPSIS
Exports a recovery plan result object to XML format

.PARAMETER RecoveryPlanResult
The recovery plan result to export
#>
Function Export-RecoveryPlanResultAsXml {
    [cmdletbinding()]
    Param(
        [Parameter (Mandatory=$true, ValueFromPipeline=$true, Position=1)][VMware.VimAutomation.Srm.Views.SrmRecoveryResult] $RecoveryPlanResult,
        [VMware.VimAutomation.Srm.Types.V1.SrmServer] $SrmServer
    )

    $api = Get-ServerApiEndpoint -SrmServer $SrmServer

    $RecoveryPlan = $RecoveryPlanResult.Plan
    $history = $api.Recovery.GetHistory($RecoveryPlan.MoRef)
    $lines = $history.GetResultLength($RecoveryPlanResult.Key)
    [xml] $history.RetrieveStatus($RecoveryPlanResult.Key, 0, $lines)
}

<#
.SYNOPSIS
Add a protection group to a recovery plan. This requires SRM 5.8 or later.

.PARAMETER RecoveryPlan
The recovery plan the protection group will be associated with

.PARAMETER ProtectionGroup
The protection group to associate with the recovery plan
#>
Function Add-ProtectionGroup {
    [cmdletbinding()]
    Param(
        [Parameter (Mandatory=$true, Position=1)][VMware.VimAutomation.Srm.Views.SrmRecoveryPlan] $RecoveryPlan,
        [Parameter (Mandatory=$true, ValueFromPipeline=$true, Position=2)][VMware.VimAutomation.Srm.Views.SrmProtectionGroup] $ProtectionGroup
    )

    if ($RecoveryPlan -and $ProtectionGroup) {
        foreach ($pg in $ProtectionGroup) {
            try {
                $RecoveryPlan.AddProtectionGroup($pg.MoRef)
            } catch {
                Write-Error $_
            }
        }
    }
}

<#
.SYNOPSIS
Get the recovery settings of a protected VM. This requires SRM 5.8 or later.

.PARAMETER RecoveryPlan
The recovery plan the settings will be retrieved from.

.PARAMETER Vm
The virtual machine to retieve recovery settings for.

#>
Function Get-RecoverySettings {
    [cmdletbinding()]
    Param(
        [Parameter (Mandatory=$true)][VMware.VimAutomation.Srm.Views.SrmRecoveryPlan] $RecoveryPlan,
        [Parameter (ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine] $Vm,
        [Parameter (ValueFromPipeline=$true)][VMware.Vim.VirtualMachine] $VmView,
        [Parameter (ValueFromPipeline=$true)][VMware.VimAutomation.Srm.Views.SrmProtectionGroupProtectedVm] $ProtectedVm
    )

    $moRef = Get_MoRefFromVmObj -Vm $Vm -VmView $VmView -ProtectedVm $ProtectedVm

    if ($RecoveryPlan -and $moRef) {
        $RecoveryPlan.GetRecoverySettings($moRef)
    }
}

<#
.SYNOPSIS
Get the recovery settings of a protected VM. This requires SRM 5.8 or later.

.PARAMETER RecoveryPlan
The recovery plan the settings will be retrieved from.

.PARAMETER Vm
The virtual machine to configure recovery settings on.

.PARAMETER RecoverySettings
The recovery settings to configure. These should have been retrieved via a
call to Get-RecoverySettings

#>
Function Set-RecoverySettings {
    [cmdletbinding()]
    Param(
        [Parameter (Mandatory=$true)][VMware.VimAutomation.Srm.Views.SrmRecoveryPlan] $RecoveryPlan,
        [Parameter (ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine] $Vm,
        [Parameter (ValueFromPipeline=$true)][VMware.Vim.VirtualMachine] $VmView,
        [Parameter (ValueFromPipeline=$true)][VMware.VimAutomation.Srm.Views.SrmProtectionGroupProtectedVm] $ProtectedVm,
        [Parameter (Mandatory=$true, ValueFromPipeline=$true)][VMware.VimAutomation.Srm.Views.SrmRecoverySettings] $RecoverySettings
    )

    
    $moRef = Get_MoRefFromVmObj -Vm $Vm -VmView $VmView -ProtectedVm $ProtectedVm

    if ($RecoveryPlan -and $moRef -and $RecoverySettings) {
        $RecoveryPlan.SetRecoverySettings($moRef, $RecoverySettings)
    }
}

<#
.SYNOPSIS
Create a new per-Vm command to add to the SRM Recovery Plan

.PARAMETER Command
The command script to execute.

.PARAMETER Description
The user friendly description of this script.

.PARAMETER Timeout
The number of seconds this command has to execute before it will be timedout.

.PARAMETER RunInRecoveredVm
For a post-power on command this flag determines whether it will run on the
recovered VM or on the SRM server.

#>
Function New-Command {
    [cmdletbinding()]
    Param(
        [Parameter (Mandatory=$true)][string] $Command,
        [Parameter (Mandatory=$true)][string] $Description,
        [int]    $Timeout = 300,
        [switch] $RunInRecoveredVm = $false
    )

    $srmWsdlCmd = New-Object VMware.VimAutomation.Srm.WsdlTypes.SrmCommand
    $srmCmd = New-Object VMware.VimAutomation.Srm.Views.SrmCommand -ArgumentList $srmWsdlCmd
    $srmCmd.Command = $Command
    $srmCmd.Description = $Description
    $srmCmd.RunInRecoveredVm = $RunInRecoveredVm
    $srmCmd.Timeout = $Timeout
    $srmCmd.Uuid = [guid]::NewGuid()

    $srmCmd
}

<# Internal function #>
Function Add_Command {
    [cmdletbinding()]
    Param(
        [Parameter (Mandatory=$true, ValueFromPipeline=$true)][VMware.VimAutomation.Srm.Views.SrmRecoverySettings] $RecoverySettings,
        [Parameter (Mandatory=$true)][VMware.VimAutomation.Srm.Views.SrmCommand] $SrmCommand,
        [Parameter (Mandatory=$true)][bool] $PostRecovery
    )

    if ($PostRecovery) {
        $commands = $RecoverySettings.PostPowerOnCallouts
    } else {
        $commands = $RecoverySettings.PrePowerOnCallouts
    }

    if (-not $commands) {
        $commands = New-Object System.Collections.Generic.List[VMware.VimAutomation.Srm.Views.SrmCallout]
    }
    $commands.Add($SrmCommand)

    if ($PostRecovery) {
        $RecoverySettings.PostPowerOnCallouts = $commands
    } else {
        $RecoverySettings.PrePowerOnCallouts = $commands
    }
}

<#
.SYNOPSIS
Add an SRM command to the set of pre recovery callouts for a VM.

.PARAMETER RecoverySettings
The recovery settings to update. These should have been retrieved via a
call to Get-RecoverySettings

.PARAMETER SrmCommand
The command to add to the list.

#>
Function Add-PreRecoveryCommand {
    [cmdletbinding()]
    Param(
        [Parameter (Mandatory=$true, ValueFromPipeline=$true)][VMware.VimAutomation.Srm.Views.SrmRecoverySettings] $RecoverySettings,
        [Parameter (Mandatory=$true)][VMware.VimAutomation.Srm.Views.SrmCommand] $SrmCommand
    )
    Add_Command -RecoverySettings $RecoverySettings -SrmCommand $SrmCommand -PostRecovery $false
    $RecoverySettings #simplify chaining
}

<#
.SYNOPSIS
Remove an SRM command from the set of pre recovery callouts for a VM.

.PARAMETER RecoverySettings
The recovery settings to update. These should have been retrieved via a
call to Get-RecoverySettings

.PARAMETER SrmCommand
The command to remove from the list.

#>
Function Remove-PreRecoveryCommand {
    [cmdletbinding()]
    Param(
        [Parameter (Mandatory=$true, ValueFromPipeline=$true)][VMware.VimAutomation.Srm.Views.SrmRecoverySettings] $RecoverySettings,
        [Parameter (Mandatory=$true)][VMware.VimAutomation.Srm.Views.SrmCommand] $SrmCommand
    )

    $RecoverySettings.PrePowerOnCallouts.Remove($SrmCommand)
    $RecoverySettings #simplify chaining
}

<#
.SYNOPSIS
Add an SRM command to the set of post recovery callouts for a VM.

.PARAMETER RecoverySettings
The recovery settings to update. These should have been retrieved via a
call to Get-RecoverySettings

.PARAMETER SrmCommand
The command to add to the list.

#>
Function Add-PostRecoveryCommand {
    [cmdletbinding()]
    Param(
        [Parameter (Mandatory=$true, ValueFromPipeline=$true)][VMware.VimAutomation.Srm.Views.SrmRecoverySettings] $RecoverySettings,
        [Parameter (Mandatory=$true)][VMware.VimAutomation.Srm.Views.SrmCommand] $SrmCommand
    )
    Add_Command -RecoverySettings $RecoverySettings -SrmCommand $SrmCommand -PostRecovery $true
    $RecoverySettings #simplify chaining
}


<#
.SYNOPSIS
Remove an SRM command from the set of post recovery callouts for a VM.

.PARAMETER RecoverySettings
The recovery settings to update. These should have been retrieved via a
call to Get-RecoverySettings

.PARAMETER SrmCommand
The command to remove from the list.

#>
Function Remove-PostRecoveryCommand {
    [cmdletbinding()]
    Param(
        [Parameter (Mandatory=$true, ValueFromPipeline=$true)][VMware.VimAutomation.Srm.Views.SrmRecoverySettings] $RecoverySettings,
        [Parameter (Mandatory=$true)][VMware.VimAutomation.Srm.Views.SrmCommand] $SrmCommand
    )

    $RecoverySettings.PostPowerOnCallouts.Remove($SrmCommand)
    $RecoverySettings #simplify chaining
}


Function New-RecoveryPlan {
    [cmdletbinding()]
    Param(
        [Parameter (Mandatory=$true)][string] $Name,
        [string] $Description,
        [VMware.VimAutomation.Srm.Views.SrmRecoveryPlanFolder] $Folder,
        [VMware.VimAutomation.Srm.Views.SrmProtectionGroup[]] $ProtectionGroups,
        [VMware.VimAutomation.Srm.Views.SrmRecoveryTestNetworkMapping[]] $TestNetworkMappings,
        [VMware.VimAutomation.Srm.Types.V1.SrmServer] $SrmServer
    )

    $api = Get-ServerApiEndpoint -SrmServer $SrmServer

    if (-not $Folder) {
        $Folder = Get-RecoveryPlanFolder -SrmServer $SrmServer
    }

    $protectionGroupmRefs += @( $ProtectionGroups | %{ $_.MoRef } | Select -Unique)

    [VMware.VimAutomation.Srm.Views.CreateRecoveryPlanTask] $task = $api.Recovery.CreateRecoveryPlan(
        $Name,
        $Folder.MoRef,
        $protectionGroupmRefs,
        $Description,
        $TestNetworkMappings
    )

    while(-not $task.IsCreateRecoveryPlanComplete()) { sleep -Seconds 1 }

    $task.GetNewRecoveryPlan()
}


Function Remove-RecoveryPlan {
    [cmdletbinding(SupportsShouldProcess=$True, ConfirmImpact="High")]
    Param(
        [Parameter (Mandatory=$true)][VMware.VimAutomation.Srm.Views.SrmRecoveryPlan] $RecoveryPlan,
        [VMware.VimAutomation.Srm.Types.V1.SrmServer] $SrmServer
    )

    $api = Get-ServerApiEndpoint -SrmServer $SrmServer

    $rpinfo = $RecoveryPlan.GetInfo()
    if ($pscmdlet.ShouldProcess($rpinfo.Name, "Remove")) {
        $api.Recovery.DeleteRecoveryPlan($RecoveryPlan.MoRef)
    }
}

Function Get-RecoveryPlanFolder {
    [cmdletbinding()]
    Param(
        [VMware.VimAutomation.Srm.Types.V1.SrmServer] $SrmServer
    )

    $api = Get-ServerApiEndpoint -SrmServer $SrmServer

    $folder = $api.Recovery.GetRecoveryPlanRootFolder()

    return $folder
}
