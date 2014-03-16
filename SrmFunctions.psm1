# SRM Helper Methods

Function Get-ProtectionGroup () {
    Param(
        [string] $Name,
        [string] $Type,
        [Parameter (ValueFromPipeline=$true)] $RecoveryPlan
    )

    $api = $global:DefaultSrmServers[0].ExtensionData

    if ($RecoveryPlan) {
        $pgs = $RecoveryPlan.GetInfo().ProtectionGroups
    } else {
        $pgs = $api.Protection.ListProtectionGroups()
    }

    $pgs | % {
        $pgi = $_.GetInfo()
        $selected = (-not $Name -or ($Name -eq $pgi.Name)) -and (-not $Type -or ($Type -eq $pgi.Type))
        if ($selected) {
            $_
        }
    }
}

Function Get-RecoveryPlan () {
    Param(
        [string] $Name,
        [Parameter (ValueFromPipeline=$true)] $ProtectionGroup
    )

    $api = $global:DefaultSrmServers[0].ExtensionData

    if($ProtectionGroup) {
        $rps = $ProtectionGroup.ListRecoveryPlans()
    } else {
        $rps = $api.Recovery.ListPlans()
    }

    $rps | % {
        $rpi = $_.GetInfo()
        $selected = (-not $Name -or ($Name -eq $rpi.Name))
        if ($selected) {
            $_
        }
    }
}

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
