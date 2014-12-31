# SRM Helper Methods - https://github.com/benmeadowcroft/SRM-Cmdlets

<#
.SYNOPSIS
This is intended to be an "internal" function only. It filters a
pipelined input of objects and elimiates duplicates as identified
by the MoRef property on the object.

.LINK
https://github.com/benmeadowcroft/SRM-Cmdlets/
#>
Function Select_UniqueByMoRef {

    Param(
        [Parameter (ValueFromPipeline=$true)] $in
    )
    process {
        $moref = New-Object System.Collections.ArrayList
        $in | sort | select MoRef -Unique | %{ $moref.Add($_.MoRef) } > $null
        $in | %{
            if ($_.MoRef -in $moref) {
                $moref.Remove($_.MoRef)
                $_ #output
            }
        }
    }
}

<#
.SYNOPSIS
This is intended to be an "internal" function only. It gets the
MoRef property of a VM from either a VM object, a VM view, or the
protected VM object.
#>
Function Get_MoRefFromVmObj {
    Param(
        [Parameter (ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Impl.V1.Inventory.VirtualMachineImpl] $Vm,
        [Parameter (ValueFromPipeline=$true)][VMware.Vim.VirtualMachine] $VmView,
        [Parameter (ValueFromPipeline=$true)][VMware.VimAutomation.Srm.Views.SrmProtectionGroupProtectedVm] $ProtectedVm
    )


    $moRef = $null
    if ($Vm.ExtensionData.MoRef) { # VM object
        $moRef = $Vm.ExtensionData.MoRef
    } elseif ($VmView.MoRef) { # VM view
        $moRef = $VmView.MoRef
    } elseif ($protectedVm) {
        $moRef = $ProtectedVm.Vm.MoRef
    }

    $moRef
}

<#
.SYNOPSIS
Retrieve the SRM Server Version
#>
Function Get-ServerVersion {
    [cmdletbinding()]
    Param(
        [VMware.VimAutomation.ViCore.Types.V1.Srm.SrmServer] $SrmServer
    )
    $srm = Get-Server $SrmServer
    $srm.Version
}

<#
.SYNOPSIS
Lookup the srm instance for a specific server.
#>
Function Get-Server {
    [cmdletbinding()]
    Param(
        [string] $SrmServerAddress,
        [VMware.VimAutomation.ViCore.Types.V1.Srm.SrmServer] $SrmServer
    )

    $found = $null

    if ($SrmServer) {
        $found = $SrmServer
    } elseif ($SrmServerAddress) {
        # search for server address in default servers
        $global:DefaultSrmServers | %{
            if ($_.Name -ieq $SrmServerAddress) {
                $found = $_
            }
        }
        if (-not $found) {
            throw "SRM server $SrmServerAddress not found. Connect-Server must be called first."
        }
    }

    if (-not $found) {
        #default result
        $found = $global:DefaultSrmServers[0]
    }

    return $found;
}

<#
.SYNOPSIS
Get the subset of protection groups matching the input criteria

.PARAMETER Name
Return protection groups matching the specified name

.PARAMETER Type
Return protection groups matching the specified protection group
type. For SRM 5.0-5.5 this is either 'san' for protection groups
consisting of a set of replicated datastores or 'vr' for vSphere
Replication based protection groups.

.PARAMETER RecoveryPlan
Return protection groups associated with a particular recovery
plan

.PARAMETER SrmServer
the SRM server to use for this operation.
#>
Function Get-ProtectionGroup {
    [cmdletbinding()]
    Param(
        [Parameter(position=1)][string] $Name,
        [string] $Type,
        [Parameter (ValueFromPipeline=$true)][VMware.VimAutomation.Srm.Views.SrmRecoveryPlan[]] $RecoveryPlan,
        [VMware.VimAutomation.ViCore.Types.V1.Srm.SrmServer] $SrmServer
    )
    begin {
        $srm = Get-Server $SrmServer
        $api = $srm.ExtensionData
        $pgs = @()
    }
    process {
        if ($RecoveryPlan) {
            foreach ($rp in $RecoveryPlan) {
                $pgs += $RecoveryPlan.GetInfo().ProtectionGroups
            }
            $pgs = Select_UniqueByMoRef($pgs)
        } else {
            $pgs += $api.Protection.ListProtectionGroups()
        }
    }
    end {
        $pgs | % {
            $pgi = $_.GetInfo()
            $selected = (-not $Name -or ($Name -eq $pgi.Name)) -and (-not $Type -or ($Type -eq $pgi.Type))
            if ($selected) {
                $_
            }
        }
    }
}

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
        [VMware.VimAutomation.ViCore.Types.V1.Srm.SrmServer] $SrmServer
    )

    begin {
        $srm = Get-Server $SrmServer
        $api = $srm.ExtensionData
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
Get the subset of protected VMs matching the input criteria

.PARAMETER Name
Return protected VMs matching the specified name

.PARAMETER State
Return protected VMs matching the specified state. For protected
VMs on the protected site this is usually 'ready', for
placeholder VMs this is 'shadowing'

.PARAMETER ProtectionGroup
Return protected VMs associated with particular protection
groups
#>
Function Get-ProtectedVM {
    [cmdletbinding()]
    Param(
        [Parameter(position=1)][string] $Name,
        [VMware.VimAutomation.Srm.Views.SrmProtectionGroupProtectionState] $State,
        [VMware.VimAutomation.Srm.Views.SrmProtectionGroupProtectionState] $PeerState,
        [switch] $ConfiguredOnly,
        [switch] $UnconfiguredOnly,
        [Parameter (ValueFromPipeline=$true)][VMware.VimAutomation.Srm.Views.SrmProtectionGroup[]] $ProtectionGroup,
        [Parameter (ValueFromPipeline=$true)][VMware.VimAutomation.Srm.Views.SrmRecoveryPlan[]] $RecoveryPlan,
        [string] $ProtectionGroupName,
        [VMware.VimAutomation.ViCore.Types.V1.Srm.SrmServer] $SrmServer
    )

    if ($null -eq $ProtectionGroup) {
        $ProtectionGroup = Get-ProtectionGroup -Name $ProtectionGroupName -RecoveryPlan $RecoveryPlan -SrmServer $SrmServer
    }
    $ProtectionGroup | % {
        $pg = $_
        $pg.ListProtectedVms() | % {
            # try and update the view data for the protected VM
            try {
                $_.Vm.UpdateViewData()
            } catch {
                Write-Error $_            
            } finally {
                $_
            }
        } | Where-object { -not $Name -or ($Name -eq $_.Vm.Name) } |
            where-object { -not $State -or ($State -eq $_.State) } |
            where-object { -not $PeerState -or ($PeerState -eq $_.PeerState) } |
            where-object { ($ConfiguredOnly -and $_.NeedsConfiguration -eq $false) -or ($UnconfiguredOnly -and $_.NeedsConfiguration -eq $true) -or (-not $ConfiguredOnly -and -not $UnconfiguredOnly) }
    }
}

<#
.SYNOPSIS
Get the unprotected VMs that are associated with a protection group

.PARAMETER ProtectionGroup
Return unprotected VMs associated with particular protection
groups. For VR protection groups this is VMs that are associated
with the PG but not configured, For ABR protection groups this is
VMs on replicated datastores associated with the group that are not
configured.
#>
Function Get-UnProtectedVM {
    [cmdletbinding()]
    Param(
        [Parameter (ValueFromPipeline=$true)][VMware.VimAutomation.Srm.Views.SrmProtectionGroup[]] $ProtectionGroup,
        [Parameter (ValueFromPipeline=$true)][VMware.VimAutomation.Srm.Views.SrmRecoveryPlan[]] $RecoveryPlan,
        [string] $ProtectionGroupName,
        [VMware.VimAutomation.ViCore.Types.V1.Srm.SrmServer] $SrmServer
    )

    if ($null -eq $ProtectionGroup) {
        $ProtectionGroup = Get-ProtectionGroup -Name $ProtectionGroupName -RecoveryPlan $RecoveryPlan -SrmServer $SrmServer
    }

    $associatedVMs = @()
    $protectedVmRefs = @()

    $ProtectionGroup | % {
        $pg = $_
        # For VR listAssociatedVms to get list of VMs
        if ($pg.GetInfo().Type -eq 'vr') {
            $associatedVMs += @($pg.ListAssociatedVms() | Get-VIObjectByVIView)
        }
        # TODO test this: For ABR get VMs on GetProtectedDatastore
        if ($pg.GetInfo().Type -eq 'san') {
            $pds = @(Get-ProtectedDatastore -ProtectionGroup $pg)
            $pds | % {
                $ds = Get-Datastore -id $_.MoRef
                $associatedVMs += @(Get-VM -Datastore $ds)
            }
        }

        # get protected VMs
        $protectedVmRefs += @(Get-ProtectedVM -ProtectionGroup $pg | %{ $_.Vm.MoRef } | Select -Unique)
    }

    # get associated but unprotected VMs
    $associatedVMs | where { $protectedVmRefs -notcontains $_.ExtensionData.MoRef }
}

<#
.SYNOPSIS
Get the placeholder VMs that are associated with SRM
#>
Function Get-PlaceholderVM {
    [cmdletbinding()]
    Param()
    Get-VM @Args | where {$_.ExtensionData.Config.ManagedBy.extensionKey -like "com.vmware.vcDr*" -and $_.ExtensionData.Config.ManagedBy.Type -ieq 'placeholderVm'}
}

<#
.SYNOPSIS
Get the test VMs that are associated with SRM
#>
Function Get-TestVM {
    [cmdletbinding()]
    Param()
    Get-VM @Args | where {$_.ExtensionData.Config.ManagedBy.extensionKey -like "com.vmware.vcDr*" -and $_.ExtensionData.Config.ManagedBy.Type -ieq 'testVm'}
}

#Untested as I don't have ABR setup in my lab yet
<#
.SYNOPSIS
Get the subset of protected Datastores matching the input criteria

.PARAMETER ProtectionGroup
Return protected datastores associated with particular protection
groups
#>
Function Get-ProtectedDatastore {
    [cmdletbinding()]
    Param(
        [Parameter (ValueFromPipeline=$true)][VMware.VimAutomation.Srm.Views.SrmProtectionGroup[]] $ProtectionGroup,
        [Parameter (ValueFromPipeline=$true)][VMware.VimAutomation.Srm.Views.SrmRecoveryPlan[]] $RecoveryPlan,
        [string] $ProtectionGroupName,
        [VMware.VimAutomation.ViCore.Types.V1.Srm.SrmServer] $SrmServer
    )

    if (-not $ProtectionGroup) {
        $ProtectionGroup = Get-ProtectionGroup -Name $ProtectionGroupName -RecoveryPlan $RecoveryPlan -SrmServer $SrmServer
    }
    $ProtectionGroup | % {
        $pg = $_
        if ($pg.GetInfo().Type -eq 'san') { # only supported for array based replication datastores
            $pg.ListProtectedDatastores()
        }
    }
}


<#
.SYNOPSIS
Protect a VM using SRM

.PARAMETER ProtectionGroup
The protection group that this VM will belong to

.PARAMETER Vm
The virtual machine to protect
#>
Function Protect-VM {
    [cmdletbinding()]
    Param(
        [Parameter (Mandatory=$true)][VMware.VimAutomation.Srm.Views.SrmProtectionGroup] $ProtectionGroup,
        [Parameter (ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Impl.V1.Inventory.VirtualMachineImpl] $Vm,
        [Parameter (ValueFromPipeline=$true)][VMware.Vim.VirtualMachine] $VmView
    )

    $moRef = Get_MoRefFromVmObj -Vm $Vm -VmView $VmView

    $pgi = $ProtectionGroup.GetInfo()
    #TODO query protection status first

    if ($moRef) {
        if ($pgi.Type -eq 'vr') {
            $ProtectionGroup.AssociateVms(@($moRef))
        }
        $protectionSpec = New-Object VMware.VimAutomation.Srm.Views.SrmProtectionGroupVmProtectionSpec
        $protectionSpec.Vm = $moRef
        $protectTask = $ProtectionGroup.ProtectVms($protectionSpec)
        while(-not $protectTask.IsComplete()) { sleep -Seconds 1 }
        $protectTask.GetResult()
    } else {
        throw "Can't protect the VM, no MoRef found."
    }
}


<#
.SYNOPSIS
Unprotect a VM using SRM

.PARAMETER ProtectionGroup
The protection group that this VM will be removed from

.PARAMETER Vm
The virtual machine to unprotect
#>
Function Unprotect-VM {
    [cmdletbinding()]
    Param(
        [Parameter (Mandatory=$true)][VMware.VimAutomation.Srm.Views.SrmProtectionGroup] $ProtectionGroup,
        [Parameter (ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Impl.V1.Inventory.VirtualMachineImpl] $Vm,
        [Parameter (ValueFromPipeline=$true)][VMware.Vim.VirtualMachine] $VmView,
        [Parameter (ValueFromPipeline=$true)][VMware.VimAutomation.Srm.Views.SrmProtectionGroupProtectedVm] $ProtectedVm
    )

    $moRef = Get_MoRefFromVmObj -Vm $Vm -VmView $VmView -ProtectedVm $ProtectedVm

    $pgi = $ProtectionGroup.GetInfo()
    $protectTask = $ProtectionGroup.UnprotectVms($moRef)
    while(-not $protectTask.IsComplete()) { sleep -Seconds 1 }
    if ($pgi.Type -eq 'vr') {
        $ProtectionGroup.UnassociateVms(@($moRef))
    }
    $protectTask.GetResult()
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
        [VMware.VimAutomation.ViCore.Types.V1.Srm.SrmServer] $SrmServer
    )

    $srm = Get-Server $SrmServer
    $api = $srm.ExtensionData

    # Get the history objects
    $history = $api.Recovery.GetHistory($RecoveryPlan.MoRef)
    $results = $history.GetRecoveryResult($history.GetResultCount())

    $results |
        Where-Object { -not $RecoveryMode -or $_.RunMode -eq $RecoveryMode } |
        Where-Object { -not $ResultState -or $_.ResultState -eq $ResultState } |
        Where-Object { $null -eq $StartedAfter -or $_.StartTime -gt $StartedAfter } |
        Where-Object { $null -eq $StartedBefore -or $_.StartTime -lt $StartedBefore }
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
        [VMware.VimAutomation.ViCore.Types.V1.Srm.SrmServer] $SrmServer
    )

    $srm = Get-Server $SrmServer
    $api = $srm.ExtensionData

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
        [Parameter (ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Impl.V1.Inventory.VirtualMachineImpl] $Vm,
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
        [Parameter (ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Impl.V1.Inventory.VirtualMachineImpl] $Vm,
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
