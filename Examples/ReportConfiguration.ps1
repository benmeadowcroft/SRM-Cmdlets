# Depends on SRM Helper Methods - https://github.com/benmeadowcroft/SRM-Cmdlets
# It is assumed that the conenct to VC and SRM Server have alrady been made

Function Get-SrmConfigReportSite {
    Param(
        [VMware.VimAutomation.ViCore.Types.V1.Srm.SrmServer] $SrmServer
    )

    Get-SrmServer $SrmServer |
        Format-Table -Wrap -AutoSize @{Label="SRM Site Name"; Expression={$_.ExtensionData.GetSiteName()} },
            @{Label="SRM Peer Site Name"; Expression={$_.ExtensionData.GetPairedSite().Name} },
            @{Label="SRM Host"; Expression={$_.Name} },
            @{Label="SRM Port"; Expression={$_.Port} },
            @{Label="Version"; Expression={$_.Version} },
            @{Label="Build"; Expression={$_.Build}}
}

Function Get-SrmConfigReportPlan {
    Param(
        [VMware.VimAutomation.ViCore.Types.V1.Srm.SrmServer] $SrmServer
    )

    Get-RecoveryPlan -SrmServer $SrmServer | %{
        $rp = $_
        $rpinfo = $rp.GetInfo()
        $peerState = $rp.GetPeer().State
        $pgs = Get-ProtectionGroup -RecoveryPlan $rp
        $pgnames = $pgs | %{ $_.GetInfo().Name }

        $output = "" | select plan, state, peerState, groups
        $output.plan = $rpinfo.Name
        $output.state = $rpinfo.State
        $output.peerState = $peerState
        $output.groups = [string]::Join(",`r`n", $pgnames)

        $output
    } | Format-Table -Wrap -AutoSize @{Label="Recovery Plan Name"; Expression={$_.plan} },
                                   @{Label="Recovery State"; Expression={$_.state} },
                                   @{Label="Peer Recovery State"; Expression={$_.peerState} },
                                   @{Label="Protection Groups"; Expression={$_.groups}}
}


Function Get-SrmConfigReportProtectionGroup {
    Param(
        [VMware.VimAutomation.ViCore.Types.V1.Srm.SrmServer] $SrmServer
    )

    Get-ProtectionGroup -SrmServer $SrmServer | %{
        $pg = $_
        $pginfo = $pg.GetInfo()
        $pgstate = $pg.GetProtectionState()
        $peerState = $pg.GetPeer().State
        $rps = Get-RecoveryPlan -ProtectionGroup $pg
        $rpnames = $rps | %{ $_.GetInfo().Name }

        $output = "" | select name, type, state, peerState, plans
        $output.name = $pginfo.Name
        $output.type = $pginfo.Type
        $output.state = $pgstate
        $output.peerState = $peerState
        $output.plans = [string]::Join(",`r`n", $rpnames)

        $output
    } | Format-Table -Wrap -AutoSize @{Label="Protection Group Name"; Expression={$_.name} },
                                   @{Label="Type"; Expression={$_.type} },
                                   @{Label="Protection State"; Expression={$_.state} },
                                   @{Label="Peer Protection State"; Expression={$_.peerState} },
                                   @{Label="Recovery Plans"; Expression={$_.plans} }
}


Function Get-SrmConfigReportProtectedDatastore {
    Param(
        [VMware.VimAutomation.ViCore.Types.V1.Srm.SrmServer] $SrmServer
    )

    Get-ProtectionGroup -SrmServer $SrmServer -Type "san" | %{
        $pg = $_
        $pginfo = $pg.GetInfo()
        $pds = Get-ProtectedDatastore -ProtectionGroup $pg
        $pds | %{
            $pd = $_
            $output = "" | select datacenter, group, name, capacity, free
            $output.datacenter = $pd.Datacenter.Name
            $output.group = $pginfo.Name
            $output.name = $pd.Name
            $output.capacity = $pd.CapacityGB
            $output.free = $pd.FreeSpaceGB

            $output

        }
    } | Format-Table -Wrap -AutoSize -GroupBy "datacenter" @{Label="Datastore Name"; Expression={$_.name} },
                                   @{Label="Capacity GB"; Expression={$_.capacity} },
                                   @{Label="Free GB"; Expression={$_.free} },
                                   @{Label="Protection Group"; Expression={$_.group} }
}


Function Get-SrmConfigReportProtectedVm {
    Param(
        [VMware.VimAutomation.ViCore.Types.V1.Srm.SrmServer] $SrmServer
    )

    $srmversion = Get-SrmVersion -SrmServer $SrmServer
    Get-ProtectionGroup -SrmServer $SrmServer | %{
        $pg = $_
        $pginfo = $pg.GetInfo()
        $pvms = Get-ProtectedVM -ProtectionGroup $pg
        $rps = Get-RecoveryPlan -ProtectionGroup $pg
        $rpnames = $rps | %{ $_.GetInfo().Name }
        $pvms | %{
            $pvm = $_
            if ($srmversion.StartsWith("5.8")) {
                $rs = $rps | Select -First 1 | %{ $_.GetRecoverySettings($pvm.Vm.MoRef) }
            }
            $output = "" | select group, name, state, peerState, plans, priority, finalPowerState
            $output.group = $pginfo.Name
            $output.name = $pvm.Vm.Name
            $output.state = $pvm.State
            $output.peerState = $pvm.PeerState
            $output.plans = [string]::Join(",`r`n", $rpnames)
            if ($rs) {
                $output.priority = $rs.RecoveryPriority
                $output.finalPowerState = $rs.FinalPowerState
            }
            $output

        }
    } | Format-Table -Wrap -AutoSize @{Label="VM Name"; Expression={$_.name} },
                                   @{Label="VM Protection State"; Expression={$_.state} },
                                   @{Label="VM Peer Protection State"; Expression={$_.peerState} },
                                   @{Label="Protection Group"; Expression={$_.group} },
                                   @{Label="Recovery Plans"; Expression={$_.plans} },
                                   @{Label="Recovery Priority"; Expression={$_.priority} },
                                   @{Label="Final Power State"; Expression={$_.finalPowerState} }
    
}

Function Get-SrmConfigReport {
    Param(
        [VMware.VimAutomation.ViCore.Types.V1.Srm.SrmServer] $SrmServer
    )

    Get-SrmConfigReportSite -SrmServer $SrmServer
    Get-SrmConfigReportPlan -SrmServer $SrmServer
    Get-SrmConfigReportProtectionGroup -SrmServer $SrmServer
    Get-SrmConfigReportProtectedDatastore -SrmServer $SrmServer
    Get-SrmConfigReportProtectedVm -SrmServer $SrmServer
}