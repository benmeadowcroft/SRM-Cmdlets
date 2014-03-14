# Add-PSSnapin Vmware*

# SRM Helper Methods

Function Get-ProtectionGroup ($Name, $Type) {
    $api = $global:DefaultSrmServers[0].ExtensionData

    $api.Protection.ListProtectionGroups() | % {
        $pgi = $_.GetInfo()
        $selected = (-not $Name -or ($Name -eq $pgi.Name)) -and (-not $Type -or ($Type -eq $pgi.Type))
        if ($selected) {
            $_
        }
    }
}

Function Get-RecoveryPlan ($Name) {
    $api = $global:DefaultSrmServers[0].ExtensionData

    $api.Recovery.ListPlans() | % {
        $rpi = $_.GetInfo()
        $selected = (-not $Name -or ($Name -eq $rpi.Name))
        if ($selected) {
            $_
        }
    }
}

Function Get-ProtectedVM ($Name, $State, $ProtectionGroup, $ProtectionGroupName) {
    if (-not $ProtectionGroup) {
        $ProtectionGroup = Get-ProtectionGroup -Name $ProtectionGroupName
    }
    $ProtectionGroup | % {
        $pg = $_
        $pg.ListProtectedVms() | % {
            if ($Name) {
                $_.Vm.UpdateViewData()
            }
            $selected = $selected -and (-not $Name -or ($Name -eq $_.Vm.Name))
            $selected = $selected -and (-not $State -or ($State -eq $_.State))
            if ($selected) {
                $_
            }
        }
    }
}

#Untested as I don't have ABR setup in my lab yet
Function Get-ProtectedDatastore ($ProtectionGroup, $ProtectionGroupName) {
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

Function Protect-VM ($ProtectionGroup, $Vm) {
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

Function Unprotect-VM ($ProtectionGroup, $Vm) {
    $pgi = $ProtectionGroup.GetInfo()
    $protectTask = $ProtectionGroup.UnprotectVms($Vm.ExtensionData.MoRef)
    while(-not $protectTask.IsComplete()) { sleep -Seconds 1 }
    if ($pgi.Type -eq 'vr') {
        $ProtectionGroup.UnassociateVms(@($vm.ExtensionData.MoRef))
    }
    $protectTask.GetResult()
}
