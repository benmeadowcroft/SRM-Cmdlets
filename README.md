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

### List Virtual Machines

Goal: Create a simple report listing the VMs protected by SRM and the protection group they belong to.

        Get-ProtectionGroup | %{
          $pg = $_
          Get-ProtectedVM -ProtectionGroup $pg } | %{
          $output = "" | select VmName, PgName
          $output.VmName = $_.Vm.Name
          $output.PgName = $pg.GetInfo().Name
          $output
        }  | Format-Table @{Label="VM Name"; Expression={$_.VmName} },
                          @{Label="Protection group name"; Expression={$_.PgName} }
