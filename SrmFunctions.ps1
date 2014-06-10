# SRM Helper Methods - https://github.com/benmeadowcroft/SRM-Cmdlets

<#
.SYNOPSIS
This is intended to be an "internal" function only. It filters a
pipelined input of objects and elimiates duplicates as identified
by the MoRef property on the object.

.LINK
https://github.com/benmeadowcroft/SRM-Cmdlets/
#>
Function Select-UniqueByMoRef() { #TODO: don't export when packaged as a module

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
#>
Function Get-ProtectionGroup () {
    Param(
        [string] $Name,
        [string] $Type,
        [Parameter (ValueFromPipeline=$true)] $RecoveryPlan
    )
    begin {
        $api = $global:DefaultSrmServers[0].ExtensionData
        $pgs = @()
    }
    process {
        if ($RecoveryPlan) {
            foreach ($rp in $RecoveryPlan) {
                $pgs += $RecoveryPlan.GetInfo().ProtectionGroups
            }
            $pgs = Select-UniqueByMoRef($pgs)
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
Function Get-RecoveryPlan () {
    Param(
        [string] $Name,
        [Parameter (ValueFromPipeline=$true)] $ProtectionGroup
    )

    begin {
        $api = $global:DefaultSrmServers[0].ExtensionData
        $rps = @()
    }
    process {
        if ($ProtectionGroup) {
            foreach ($pg in $ProtectionGroup) {
                $rps += $pg.ListRecoveryPlans()
            }
            $rps = Select-UniqueByMoRef($rps)
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
Function Get-ProtectedVM () {
    Param(
        [string] $Name,
        [string] $State,
        [Parameter (ValueFromPipeline=$true)] $ProtectionGroup,
        [string] $ProtectionGroupName
    )

    if (-not $ProtectionGroup) {
        $ProtectionGroup = Get-ProtectionGroup -Name $ProtectionGroupName
    }
    $ProtectionGroup | % {
        $pg = $_
        $pg.ListProtectedVms() | % {
            try {
                $_.Vm.UpdateViewData()
            } catch {
                # silently ignore
            }
            
            $selected = $true
            $selected = $selected -and (-not $Name -or ($Name -eq $_.Vm.Name))
            $selected = $selected -and (-not $State -or ($State -eq $_.State))
            if ($selected) {
                $_
            }
        }
    }
}

#Untested as I don't have ABR setup in my lab yet
<#
.SYNOPSIS
Get the subset of protected Datastores matching the input criteria

.PARAMETER ProtectionGroup
Return protected datastores associated with particular protection
groups
#>
Function Get-ProtectedDatastore () {
    Param(
        [Parameter (ValueFromPipeline=$true)] $ProtectionGroup,
        [string] $ProtectionGroupName
    )

    if (-not $ProtectionGroup) {
        $ProtectionGroup = Get-ProtectionGroup -Name $ProtectionGroupName
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
Function Protect-VM () {
    Param(
        [Parameter (Mandatory=$true)] $ProtectionGroup,
        [Parameter (Mandatory=$true, ValueFromPipeline=$true)] $Vm
    )

    $pgi = $ProtectionGroup.GetInfo()
    #TODO query protection status first

    if ($pgi.Type -eq 'vr') {
        $ProtectionGroup.AssociateVms(@($vm.ExtensionData.MoRef))
    }
    $protectionSpec = New-Object VMware.VimAutomation.Srm.Views.SrmProtectionGroupVmProtectionSpec
    $protectionSpec.Vm = $Vm.ExtensionData.MoRef
    $protectTask = $ProtectionGroup.ProtectVms($protectionSpec)
    while(-not $protectTask.IsComplete()) { sleep -Seconds 1 }
    $protectTask.GetResult()  
}


<#
.SYNOPSIS
Unprotect a VM using SRM

.PARAMETER ProtectionGroup
The protection group that this VM will be removed from

.PARAMETER Vm
The virtual machine to unprotect
#>
Function Unprotect-VM () {
    Param(
        [Parameter (Mandatory=$true)] $ProtectionGroup,
        [Parameter (Mandatory=$true, ValueFromPipeline=$true)] $Vm
    )

    $pgi = $ProtectionGroup.GetInfo()
    $protectTask = $ProtectionGroup.UnprotectVms($Vm.ExtensionData.MoRef)
    while(-not $protectTask.IsComplete()) { sleep -Seconds 1 }
    if ($pgi.Type -eq 'vr') {
        $ProtectionGroup.UnassociateVms(@($vm.ExtensionData.MoRef))
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
Function Start-RecoveryPlan () {
    [cmdletbinding(SupportsShouldProcess=$True,ConfirmImpact="High")]
    Param(
        [Parameter (Mandatory=$true, ValueFromPipeline=$true)] $RecoveryPlan,
        [VMware.VimAutomation.Srm.Views.SrmRecoveryPlanRecoveryMode] $RecoveryMode = 'Test'
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
Function Stop-RecoveryPlan () {
    [cmdletbinding(SupportsShouldProcess=$True,ConfirmImpact="High")]
    Param(
        [Parameter (Mandatory=$true, ValueFromPipeline=$true)] $RecoveryPlan
    )

    # Validate with informative error messages
    $rpinfo = $RecoveryPlan.GetInfo()

    # Prompt the user to confirm they want to cancel the running action
    if ($pscmdlet.ShouldProcess($rpinfo.Name, 'Cancel')) {

        $RecoveryPlan.Cancel()
    }
}

#TODO: When packaged as a module export public members
# Export-ModuleMember -function Get-ProtectionGroup, Get-RecoveryPlan, Get-ProtectedVM, Get-ProtectedDatastore, Protect-VM, Unprotect-VM
