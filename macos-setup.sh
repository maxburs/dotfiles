rm -rf ~/Library/Application\ Support/Code/User/settings.json
ln ./vscode.json ~/Library/Application\ Support/Code/User/settings.json

rm -rf ~/.gitconfig
ln ./.gitconfig ~/.gitconfig

git config --global credential.helper osxkeychain

chsh -s /bin/bash
