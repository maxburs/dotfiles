Set-ExecutionPolicy RemoteSigned

$myProfile=@'
function prompt {
  $p = Split-Path -leaf -path (Get-Location)
  "$p $ "
}
'@

New-Item -path $profile -type file –force -Value $myProfile

# chocolaty
Set-ExecutionPolicy Bypass -Scope Process -Force;
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072;
iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'));

choco install git
choco install nodejs --version=12.20.1

New-Item $home -Name "workspace" -ItemType "directory"
Add-MpPreference -ExclusionPath "$($home)\workspace"

