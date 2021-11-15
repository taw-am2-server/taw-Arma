<#
.SYNOPSIS
    A POSH script to update an arma3 server that's been created with Setup-Arma3Server.ps1

.PARAMETER SteamCMDinstallPath

    The location of SteamCMD.

.PARAMETER Arma3ServerName

    Name of the Arma3 server.

.PARAMETER ServerConfigFileLocation

    The name of the config file for the server, if you use one. Should ideally be in the Arma 3 Server directory.

.PARAMETER ModsToUpdate

    A list of mods to update, using their steam numbers in the format of: "000000","000001","00125"

.NOTES
    AUTHOR: Caius Ajiz
    WEBSITE: https://github.com/CaiusAjiz/Arma3Powershell/
#>

function Update-Arma3Server {
Param(
    [Parameter(Mandatory=$true)]
    [String]$SteamCMDinstallPath,
    [Parameter(Mandatory=$true)]
    [String]$Arma3ServerName,
    [Parameter(Mandatory=$false)]
    [String[]]$ModsToUpdate
)

[string]$userName = 'taw_arma3_bat2'
[string]$passwordText = Get-Content 'F:\Documents\TAW-Arma\Secure.txt'
# # Write-Output($passwordText)
#
# # Convert to secure string
[SecureString]$securePwd = $passwordText | ConvertTo-SecureString
#
# # Create credential object
[PSCredential]$credObject = New-Object System.Management.Automation.PSCredential -ArgumentList $userName, $securePwd



##### Variables #####
#App ID is 233780 for Arma3 Server
$AppID = '233780'
$Arma3Id = '107410'
$WorkShopPath = $SteamCMDinstallPath + '\steamapps\workshop\content\107410\'
$CredentialFile = 'ServerLogin.cred'
$OriginalLocation = Get-Location
$AppInstallDir = $SteamCMDinstallPath + "\" + $Arma3ServerName
##### /Variables #####
$CredentialHash = Import-Clixml -Path "$SteamCMDinstallPath\$CredentialFile"
$UserName = $CredentialHash.Username
$Password = (New-Object System.Management.Automation.PSCredential -ArgumentList $CredentialHash.Username,$CredentialHash.Password).GetNetworkCredential().Password

#1. Check SteamCMD exists.
Set-Location -Path $SteamCMDinstallPath
$SteamCMDCheck = Test-Path -Path ".\Steamcmd.exe"

#2. Getting credentials to pass to SteamCMD as the account you use for this needs to have Arma3 bought, or mods will fail with "ERROR! Download item [Number] failed (Failure)"

#Updates Arma3 server and validates files
If($SteamCMDCheck -eq "True"){
        .\SteamCMD.exe +login $credObject  +force_install_dir $AppInstallDir +app_update $AppID validate +quit
    }else{
        throw "SteamCMD doesn't exist in $SteamCmdDir, exiting"
         }
#Installs mods to .\steamcmd\steamapps\workshop\content\107410. can't be changed. Then makes a link in the correct area so it can be called later.
Foreach ($Mod in $ModsToUpdate){
    #Mod DL from workshop
    .\SteamCMD.exe +login $credObject."userName" $credObject."Password" +workshop_download_item $Arma3Id $Mod validate +quit

    #copy folders as creating shortcuts doesn't work
    $source = $WorkShopPath + "$Mod"
    $destination = $AppInstallDir
    $destinationKeyFolder = $AppInstallDir + "\keys"
    #Copy whole Folder to the install Dir, which is required to load. Arma expects the folders to be in one area.
    Copy-Item -Path $source -Destination $destination -Recurse -Force -Verbose
    #Copy the bikeys to the Servers keys folder because nothing's ever easy.
    Get-ChildItem -Include "*bikey" -Path $source -Recurse | Copy-Item -Destination $destinationKeyFolder -Force -Verbose
}

Set-Location $OriginalLocation

}
Update-Arma3Server C:\steamcmd\SteamCMD
# Export-ModuleMember -Function Update-Arma3Server