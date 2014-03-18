# SRM Helper Methods

#TODO: make module private
Function Select-UniqueByMoRef() {
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

#TODO: Export-ModuleMember -function Get-ProtectionGroup, Get-RecoveryPlan, Get-ProtectedVM, Get-ProtectedDatastore, Protect-VM, Unprotect-VM
