


# Define clear text password
# [string]$userPassword = 'hr7^naD_[TYzBc$D'
#
# # Crete credential Object
# [SecureString]$secureString = $userPassword | ConvertTo-SecureString -AsPlainText -Force
#
# # Get content of the string
# [string]$stringObject = ConvertFrom-SecureString $secureString
#
# # Save Content to file
# $stringObject | Set-Content -Path 'Secure.txt'


Install-Module -Name SteamPS
Install-SteamCMD -InstallPath "C:\steamcmd"  -Force
# Define Credentials
[string]$userName = 'taw_arma3_bat2'
[string]$passwordText = Get-Content 'F:\Documents\TAW-Arma\Secure.txt'
# # Write-Output($passwordText)
#
# # Convert to secure string
[SecureString]$securePwd = $passwordText | ConvertTo-SecureString
#
# # Create credential object
[PSCredential]$credObject = New-Object System.Management.Automation.PSCredential -ArgumentList $userName, $securePwd



$players = 0
for ($i=2003; $i -le 4003; $i=$i+100 ) {

    try {
        $serverinfo = Get-SteamServerInfo -IPAddress 168.119.91.85 -Port $i -Timeout 100 -ErrorAction 'silentlycontinue';
#         Write-Host $serverinfo."Players";
        $players = $players+ $serverinfo."Players"
        } #try
    catch {
    } #catch


} #for

Write-Host $players;
if ($players -eq 0) {
    Write-Host "no players"



}
else {
Write-Host "Some players"}


Update-SteamApp -ApplicationName 'Arma 3 Server' -Path 'F:\A3_server' -Credential $credObject -Force

