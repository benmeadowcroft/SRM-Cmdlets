# A short script to reload the module during development

$module = Get-Module Meadowcroft.Srm

if ($module) {
    Remove-Module -Name Meadowcroft.SRM
}
Import-Module -Name $PSScriptRoot\source\Meadowcroft.SRM\Meadowcroft.Srm.psd1
