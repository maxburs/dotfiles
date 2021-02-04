rm -rf ~/.config/Code/User/settings.json
ln ./vscode.json ~/.config/Code/User/settings.json

rm -rf ~/.gitconfig
ln ./.gitconfig ~/.gitconfig

## Node + Yarn

# https://github.com/nvm-sh/nvm#install--update-script
# curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.37.2/install.sh | bash
# nvm install --lts

# https://classic.yarnpkg.com/en/docs/install
# npm install --global yarn
