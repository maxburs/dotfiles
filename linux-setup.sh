rm -rf ~/.config/Code/User/settings.json
ln ./vscode.json ~/.config/Code/User/settings.json

rm -rf ~/.gitconfig
ln ./.gitconfig ~/.gitconfig

# Node + Yarn
# curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.37.2/install.sh | bash
# nvm install --lts
# npm install --global yarn
