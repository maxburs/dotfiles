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
choco install nodejs --version=14.15.4
choco install 7zip

New-Item $home -Name "workspace" -ItemType "directory"
Add-MpPreference -ExclusionPath "$($home)\workspace"

git config --global users.name "Maxwell Burson"
git config --global user.email
git config --global core.editor "code"

refreshenv
