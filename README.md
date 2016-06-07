# SRM-Cmdlets

Helper functions for working with SRM and PowerCLI 5.5R2 or later. PowerShell 3.0 and above is required.

These are provided for illustrative/educational purposes.


## Getting Started

### Build or Download SRM-Cmdlets.zip

Either:

 - Download the `SRM-Cmdlets.zip` file from http://www.benmeadowcroft.com/projects/srm-cmdlets-for-powercli/

Or:

 - Build `SRM-Cmdlets.zip` file by checking out the project and running build.ps1 from the projects root directory. This will create the distributable zip file in the dist directory.

### Deploy SRM-Cmdlets module

 - Take `Srm-Cmdlets.zip` and extract the contents into the powershell module path. See [Microsoft's Installing Modules instructions](http://msdn.microsoft.com/en-us/library/dd878350) for more details.
 - Open PowerCLI 5.5 R2 or 5.8 R1 prompt
 - Verify You are running with PowerShell v3 or later

        $PSVersionTable.PSVersion

 - Import the SRM-Cmdlets module

        Import-Module Meadowcroft.SRM

The module uses the default prefix of `Srm` for the custom functions it defines. This can be overridden when importing the module by setting the value of the `-Prefix` parameter to something else when calling `Import-Module`.

### Connecting to SRM

Now let's connect to the SRM server. Details of how to do this are located in the [PowerCLI 5.5 R2 User's Guide](http://pubs.vmware.com/vsphere-55/topic/com.vmware.powercli.ug.doc/GUID-A5F206CF-264D-4565-8CB9-4ED1C337053F.html)

    $credential = Get-Credential
    Connect-VIServer -Server vc-a.example.com -Credential $credential
    Connect-SrmServer -Credential $credential -RemoteCredential $credential

At this point we've just been using the cmdlets provided by PowerCLI, the PowerCLI documentation also provides some examples of how to call the SRM API to perform various tasks. In the rest of this introduction we'll perform some of those tasks using the custom functions defined in this project.

### Report the Protected Virtual Machines and Their Protection Groups

Goal: Create a simple report listing the VMs protected by SRM and the protection group they belong to.

    Get-SrmProtectionGroup | %{
        $pg = $_
        Get-SrmProtectedVM -ProtectionGroup $pg } | %{
            $output = "" | select VmName, PgName
            $output.VmName = $_.Vm.Name
            $output.PgName = $pg.GetInfo().Name
            $output
        } | Format-Table @{Label="VM Name"; Expression={$_.VmName} },
                         @{Label="Protection group name"; Expression={$_.PgName}
    }

### Report the Last Recovery Plan Test

Goal: Create a simple report listing the state of the last test of a recovery plan

    Get-SrmRecoveryPlan | %{ $_ |
        Get-SrmRecoveryPlanResult -RecoveryMode Test | select -First 1
    } | Select Name, StartTime, RunMode, ResultState | Format-Table


### Execute a Recovery Plan Test

Goal: for a specific recovery plan, execute a test failover. Note the "local" SRM server we are connected to should be the recovery site in order for this to be successful.

    Get-SrmRecoveryPlan -Name "Name of Plan" | Start-SrmRecoveryPlan -RecoveryMode Test

### Export the Detailed XML Report of the Last Recovery Plan Workflow

Goal: get the XML report of the last recovery plan execution for a specific recovery plan.

    Get-SrmRecoveryPlan -Name "Name of Plan" | Get-SrmRecoveryPlanResult |
        select -First 1 | Export-RecoveryPlanResultAsXml

### Protect a Replicated VM

Goal: Take a VM replicated using vSphere Replication or Array Based Replication, add it to an appropriate protection group and configure it for protection

    $pg = Get-SrmProtectionGroup "Name of Protection Group"
    Get-VM vm-01a | Protect-SrmVM -ProtectionGroup $pg
