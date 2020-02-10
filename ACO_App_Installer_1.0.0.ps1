#Requires -Version 4.0
#Requires -RunAsAdministrator

# this script will do a clean install every time

# constants
$ErrorActionPreference = "Stop"
$displayName = "ACO_App_v1.0.0"
$keyDescription = "ACO App Key"
$keyEndDate = "1/1/2099"
$azureADModule = "AzureAD"
$version = "ACO_App_Installer_1.0.0"
$unexpectedError = "An unexpected error has occurred. Please review the following error message and try again.`n$($version)`n"
$callbackUrls = "https://api.accordo.io/partner-center/callback"

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
Get-SelfInstalledModule $azureADModule

# Sign in to AzureAD
try {
  Write-Host -ForegroundColor Yellow "  When prompted please enter the appropriate Admin credentials..."
  Connect-AzureAD | Out-Null
  $pcTenantId = $(Get-AzureADTenantDetail).ObjectId
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

# application permissions
$graphAppAccess = [Microsoft.Open.AzureAD.Model.RequiredResourceAccess]@{
  ResourceAppId  = "00000003-0000-0000-c000-000000000000"; # graph api
  ResourceAccess =
  [Microsoft.Open.AzureAD.Model.ResourceAccess]@{
    Id   = "bf394140-e372-4bf9-a898-299cfc7564e5"; # SecurityEvents.Read.All
    Type = "Role"
  },
  [Microsoft.Open.AzureAD.Model.ResourceAccess]@{
    Id   = "7ab1d382-f21e-4acd-a863-ba3e13f7da61"; # Directory.Read.All
    Type = "Role"
  },
  [Microsoft.Open.AzureAD.Model.ResourceAccess]@{
    Id   = "b0afded3-3588-46d8-8b3d-9842eff778da"; # AuditLog.Read.All
    Type = "Role"
  },
  [Microsoft.Open.AzureAD.Model.ResourceAccess]@{
    Id   = "230c1aed-a721-4c5d-9cb4-a90514e508ef"; # Reports.Read.All
    Type = "Role"
  },
  [Microsoft.Open.AzureAD.Model.ResourceAccess]@{
    Id   = "df021288-bdef-4463-88db-98f22de89214"; # User.Read.All
    Type = "Role"
  }
}

try {
  $nextStep = "Get-AzureADApplication"
  # check for pre-existing app of the same name
  Write-Host -ForegroundColor Yellow "  Checking for pre-existing app..."
  $existingapp = $null
  $existingapp = Get-AzureADApplication -SearchString $displayName
  if ($existingapp) {
    $nextStep = "Remove-AzureADApplication"
    Write-Host -ForegroundColor Yellow "  App found, removing..."
    Remove-AzureADApplication -ObjectId $existingApp.objectId
  }
  Write-Host -ForegroundColor Green "  ... no app present`n"

  $nextStep = "New-AzureADApplication"
  Write-Host -ForegroundColor Yellow "  Creating the Azure AD application..."
  $app = New-AzureADApplication -AvailableToOtherTenants $true -DisplayName $displayName -RequiredResourceAccess $graphAppAccess -ReplyUrls $callbackUrls

  $nextStep = "New-AzureADApplicationPasswordCredential"
  Write-Host -ForegroundColor Yellow "  Creating new credential..."
  $password = New-AzureADApplicationPasswordCredential -ObjectId $app.ObjectId -EndDate $keyEndDate -CustomKeyIdentifier $keyDescription

  $nextStep = "New-AzureADServicePrincipal"
  Write-Host -ForegroundColor Yellow "  Creating new service principal..."
  $spn = New-AzureADServicePrincipal -AppId $app.AppId -DisplayName $displayName

  # this adds the new service principal to admin agents. If it is not added, then consent has to be (manually) granted for each client tenant being managed
  # it should also mean that the application is consented for its application permissions (but not delegate ones)
  $nextStep = "Get-AzureADGroup"
  $adminAgentsGroup = Get-AzureADGroup -Filter "DisplayName eq 'AdminAgents'"
  if (! $adminAgentsGroup) {
    Write-Host -ForegroundColor Red "Unable to find AdminAgents group. Without this group ACO App cannot access client data without manual consent. Execution of the script will be halted"
    Exit
  }
  $nextStep = "Add-AzureADGroupMember for AdminAgents"
  Write-Host -ForegroundColor Yellow "  Adding service principal to AdminAgents group..."
  Add-AzureADGroupMember -ObjectId $adminAgentsGroup.ObjectId -RefObjectId $spn.ObjectId
}
catch {
  if ("$($Error[0].Exception)".contains("Insufficient privileges to complete the operation")) {
    Write-Host -ForegroundColor Red "The signed in user has insufficient privileges for $($nextStep). Please retry the script using an admin account for azure"
  }
  else {
    Write-Host -ForegroundColor Red $unexpectedError "Failed step: $($nextStep)" $Error[0].Exception
  }
  Exit
}

# wait 45s for the changes to propagate through active directory, so that the consent step can find the application to consent for
Write-Host -ForegroundColor Yellow "Allowing for settings propagation..."
$origpos = $host.UI.RawUI.CursorPosition
$elapsedMS = 0
$waitMS = 45000
while ($elapsedMS -le $waitMS) {
  $host.UI.RawUI.CursorPosition = $origpos
  $percentage = "{0:p0}" -f ($elapsedMS / $waitMS)
  Write-Host -ForegroundColor Yellow " $($percentage)" -NoNewline
  $elapsedMS += 500
  Start-Sleep -Milliseconds 500
}
Write-Host ""

Write-Host -ForegroundColor Green "  ... Application created, pending user consent`n"

Write-Host -ForegroundColor Green "Script complete, please update your ACO Partner Center settings to the following:"
Write-Host "ApplicationId:`nApplicationSecret:`nTenantId:`n"
Write-Host "$($app.AppId)`n$($password.Value)`n$($pcTenantId)"


