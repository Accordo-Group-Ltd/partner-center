#Requires -Version 4.0
#Requires -RunAsAdministrator

# this script will remove the ACO App

# constants
$ErrorActionPreference = "Stop"
$displayName = "ACO_App"
$azureADModule = "AzureAD"
$version = "ACO_App_Uninstaller_1.0.1"
$unexpectedError = "An unexpected error has occurred. Please review the following error message and try again.`n$($version)`n"

Write-Host -ForegroundColor Yellow "Beginning $($version)"

function Get-SelfInstalledModule {
  # we dont need to check for import as 3.0 and up will auto import for us if use the module commands
  # https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/get-module?view=powershell-6
  Write-Host -ForegroundColor Yellow "  Checking $($args[0]) PowerShell module..."
  if ( ! (Get-Module -ListAvailable -Name $args[0] )) {
    $input = Read-Host -Prompt "  $($args[0]) PowerShell module is required. Please enter [Y]es or [N]o to auto-install"
    if (($input -eq "Y") -or ($input -eq "y")) {
      Write-Host "  The $($args[0]) module installed as part of this process can be removed with the following command:"
      Write-Host "  Uninstall-Module -Name $($args[0])"
      Write-Host -ForegroundColor Yellow "  Now installing $($args[0]) module..."
      Install-Module $args[0] -Force
    }
    else {
      Write-Host -ForegroundColor Red "$($args[0]) module is required for this script to function. Exiting as it is not installed"
      Exit
    }
  }
  Write-Host -ForegroundColor Green "  ... $($azureADModule) PowerShell module loaded`n"
}

# Check if the Azure AD PowerShell module has already been loaded.
Get-SelfInstalledModule "AzureAD"

# Sign in to AzureAD
try {
  Write-Host -ForegroundColor Yellow "  When prompted please enter the appropriate Admin credentials..."
  Connect-AzureAD | Out-Null
  Write-Host -ForegroundColor Green "  ... sign in complete`n"
}
catch {
  # look at exception contents rather than type which can differ depending on set up
  if ("$($Error[0].Exception)".contains("User canceled authentication")) {
    Write-Host -ForegroundColor Red "The authentication attempt was canceled. Execution of the script will be halted"
  }
  else {
    # An unexpected error has occurred. The end-user should be notified so that the appropriate action can be taken.
    Write-Host -ForegroundColor Red $unexpectedError $Error[0].Exception
  }
  Exit
}

# find and delete pre-existing app if it exists
# this will also remove all associated permission and objects for the app
try {
  $nextStep = "Get-AzureADApplication"
  Write-Host -ForegroundColor Yellow "  Checking for pre-existing app..."
  $existingapp = $null
  $existingapp = Get-AzureADApplication -SearchString $displayName
  if ($existingapp) {
    $nextStep = "Remove-AzureADApplication"
    Write-Host -ForegroundColor Yellow "  $($displayName) found, removing..."
    Remove-AzureADApplication -ObjectId $existingApp.objectId
  }
  Write-Host -ForegroundColor Green "  ... $($displayName) successfully removed`n"
}
catch {
  if ("$($Error[0].Exception)".contains("Insufficient privileges to complete the operation")) {
    Write-Host -ForegroundColor Red "The signed in user has insufficient privileges for step: $($nextStep). Please retry the script using an admin account for azure"
  }
  else {
    Write-Host -ForegroundColor Red $unexpectedError "Failed at step: $($nextStep)" $Error[0].Exception
  }
  Exit
}