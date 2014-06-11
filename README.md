# SRM-Cmdlets

Helper functions for working with SRM and PowerCLI 5.5R2. PowerShell 3.0 and above is required.

These are provided for illustrative/educational purposes.


## Getting Started

### Pre-requisites

 - Download `SrmFunctions.ps1` and save to disk
 - Open PowerCLI 5.5 R2 prompt
 - Verify You are running with PowerShell v3 or later

        $PSVersionTable.PSVersion

 - 'dot source' `SrmFunctions.ps1` to load the custom functions into your current session

        . .\SrmFunctions.ps1

### Connecting to SRM

Now let's connect to the SRM server. Details of how to do this are located in the [PowerCLI 5.5 R2 User's Guide](http://pubs.vmware.com/vsphere-55/topic/com.vmware.powercli.ug.doc/GUID-A5F206CF-264D-4565-8CB9-4ED1C337053F.html)

    $credential = Get-Credential
    Connect-VIServer -Server vc-a.example.com -Credential $credential
    Connect-SrmServer -Credential $credential -RemoteCredential $credential

At this point we've just been using the cmdlets provided by PowerCLI, the PowerCLI documentation also provides some examples of how to call the SRM API to perform various tasks. In the rest of this introduction we'll perform some of those tasks using the custom functions defined in this project.

### Report the Protected Virtual Machines and Their Protection Groups

Goal: Create a simple report listing the VMs protected by SRM and the protection group they belong to.

    Get-ProtectionGroup | %{
        $pg = $_
        Get-ProtectedVM -ProtectionGroup $pg } | %{
            $output = "" | select VmName, PgName
            $output.VmName = $_.Vm.Name
            $output.PgName = $pg.GetInfo().Name
            $output
        } | Format-Table @{Label="VM Name"; Expression={$_.VmName} },
                         @{Label="Protection group name"; Expression={$_.PgName}
    }

### Report the Last Recovery Plan Test

Goal: Create a simple report listing the state of the last test of a recovery plan

    Get-RecoveryPlan | %{ $_ |
        Get-RecoveryPlanResult -RecoveryMode Test | select -First 1
    } | Select Name, StartTime, RunMode, ResultState | Format-Table


### Execute a Recovery Plan Test

Goal: for a specific recovery plan, execute a test failover. Note the "local" SRM server we are connected to should be the recovery site in order for this to be successful.

    Get-RecoveryPlan -Name "Name of Plan" | Start-RecoveryPlan -RecoveryMode Test

### Export the Detailed XML Report of the Last Recovery Plan Workflow

Goal: get the XML report of the last recovery plan execution for a specific recovery plan.

    Get-RecoveryPlan -Name "Name of Plan" | Get-RecoveryPlanResult |
        select -First 1 | Export-RecoveryPlanResultAsXml

### Protect a Replicated VM

Goal: Take a VM replicated using vSphere Replication or Array Based Replication, add it to an appropriate protection group and configure it for protection

    $pg = Get-ProtectionGroup "Name of Protection Group"
    Get-VM vm-01a | Protect-VM -ProtectionGroup $pg
