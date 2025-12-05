# Install command line tools (includes git)
xcode-select --install

# rm -rf ~/Library/Application\ Support/Code/User/settings.json
# ln ./vscode.json ~/Library/Application\ Support/Code/User/settings.json

# rm -rf ~/.gitconfig
# ln ./.gitconfig ~/.gitconfig

# rm -rf ~/.gitconfig
# ln ./.default-npm-packages ~/.default-npm-packages

# Use git-credential-manager instead
# git config --global credential.helper osxkeychain

git config --global core.editor "code --wait"

# Show hidden files in finder
defaults write com.apple.finder AppleShowAllFiles True
# defaults write com.apple.finder AppleShowAllFiles YES

/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# https://stackoverflow.com/a/44719239
# brew install docker --cask

## Not managed by homebrew, self updating
brew install --cask \
  obsidian \
  visual-studio-code \
  iterm2 \
  google-chrome \
  spotify

# https://asdf-vm.com/guide/getting-started.html
# ln -sf "$(pwd)/.tool-versions" ~/.tool-versions
# asdf plugin add nodejs https://github.com/asdf-vm/asdf-nodejs.git
# asdf install

asdf reshim nodejs # Must be run after every `npm install -g` call
