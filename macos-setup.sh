# rm -rf ~/Library/Application\ Support/Code/User/settings.json
# ln ./vscode.json ~/Library/Application\ Support/Code/User/settings.json

# rm -rf ~/.gitconfig
# ln ./.gitconfig ~/.gitconfig

git config --global credential.helper osxkeychain
git config --global core.editor "code --wait"

chsh -s /bin/bash
