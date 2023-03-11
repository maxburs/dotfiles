# Install command line tools (includes git)
xcode-select --install

# rm -rf ~/Library/Application\ Support/Code/User/settings.json
# ln ./vscode.json ~/Library/Application\ Support/Code/User/settings.json

# rm -rf ~/.gitconfig
# ln ./.gitconfig ~/.gitconfig

git config --global credential.helper osxkeychain
git config --global core.editor "code --wait"

# Make bash default shell
chsh -s /bin/bash

# Show hidden files in finder
defaults write com.apple.finder AppleShowAllFiles True

/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

brew install visual-studio-code
brew install iterm2
brew install google-chrome
brew install spotify
