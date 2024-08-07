Set-ExecutionPolicy RemoteSigned

# Create a dev drive: https://learn.microsoft.com/en-us/windows/dev-drive/
# Install winget: https://apps.microsoft.com/detail/9NBLGGH4NNS1
# Install Chocolatey: https://chocolatey.org/install#individual
# Change default terminal

# https://community.chocolatey.org/packages

# Set dev file locations to dev box
# https://learn.microsoft.com/en-us/windows/dev-drive/#storing-package-cache-on-dev-drive
setx /M YARN_GLOBAL_FOLDER D:\.yarn
setx /M YARN_CACHE_FOLDER D:\.yarn\cache
setx /M npm_config_cache D:\.npm\cache

# # Settings
#   Performance Options -> Fade or slide menu's into view
#   Keyboard -> Cursor blink rate -> None

# Update VsCode powershell profile

$myProfile=@'
function prompt {
  $p = Split-Path -leaf -path (Get-Location)
  "$p $ "
}
'@

New-Item -path $profile -type file -force -Value $myProfile

winget install "1Password - Password Manager"
choco install googlechrome
choco install nvm
winget install vscode
choco install git
choco install 7zip

New-Item $home -Name "workspace" -ItemType "directory"
Add-MpPreference -ExclusionPath "$($home)\workspace"

git config --global users.name "Maxwell Burson"
git config --global user.email maxwellburson@gmail.com
git config --global core.editor "code"

refreshenv

# Install Berkly Mono TTF 

# Open powershell profile: `code $profile.CurrentUserCurrentHost`

# Copy windows terminal settings
Copy-Item -Path ./windows-terminal.json -Destination %LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json
