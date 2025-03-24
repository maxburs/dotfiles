
# See https://www.nushell.sh/book/configuration.html
#
# This file is loaded after env.nu and before login.nu
#
# You can open this file in your default editor using:
# config nu

$env.config.show_banner = false
$env.config.buffer_editor = 'code'

# $env.VOLTA_HOME = '~/.volta' | path expand

$env.path ++= ['/usr/local/bin', '/opt/homebrew/bin']

# asdf config

# https://asdf-vm.com/guide/getting-started.html#_2-configure-asdf

$env.ASDF_DATA_DIR = '~/.asdf' | path expand
$env.path ++= [$"($env.ASDF_DATA_DIR)/shims" ]
. "$asdf_data_dir/completions/nushell.nu"

$env.PROMPT_COMMAND_RIGHT = ""

$env.PROMPT_COMMAND = {||  (echo $env.PWD | split row  "/" | last) }
$env.PROMPT_INDICATOR = ' % '

def bbic [] {
  brew update
  # brew bundle install --cleanup --file=~/workspace/dotfiles/brewfile.work.rb
  # brew bundle install --cleanup --file=~/workspace/dotfiles/brewfile.home.rb
  brew upgrade
}
