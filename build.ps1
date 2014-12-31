# This script will package the PowerShell files in a zip file for distribution
# It should be run from the root directory of the project

$zippath = ".\dist\SRM-Cmdlets.zip"

# Clean up before rebuilding the distributable
Remove-Item $zippath

# Create the zip file
Set-Content $zippath ("PK" + [char]5 + [char]6 + ("$([char]0)" * 18)) 

# Get COM object for the zip file
$shell = New-Object -ComObject Shell.Application
$zip = $shell.NameSpace((Get-ChildItem $zippath).FullName)

# Copy the contents of the source folder to the zip file, copying a directory
# also brings in its children so we don't need to recurse
Get-Childitem ".\source" | % { $zip.CopyHere($_.FullName) }