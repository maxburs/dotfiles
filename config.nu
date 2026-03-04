
# See https://www.nushell.sh/book/configuration.html
#
# This file is loaded after env.nu and before login.nu
#
# You can open this file in your default editor using:
# config nu

$env.config.show_banner = false
$env.config.buffer_editor = 'code'

$env.path ++= ['/usr/local/bin', '/opt/homebrew/bin']

# asdf config

# https://asdf-vm.com/guide/getting-started.html#_2-configure-asdf

$env.ASDF_NODEJS_AUTO_ENABLE_COREPACK = 'true'
$env.ASDF_NODEJS_LEGACY_FILE_DYNAMIC_STRATEGY = 'latest_available';
$env.ASDF_DATA_DIR = '~/.asdf' | path expand
$env.path ++= [$"($env.ASDF_DATA_DIR)/shims"]
source ~/.asdf/completions/nushell.nu

$env.PROMPT_COMMAND_RIGHT = ""

$env.PROMPT_COMMAND = {|| (echo $env.PWD | split row  "/" | last) }
$env.PROMPT_INDICATOR = ' % '

$env.COMPUTER_TYPE = 'work' # 'work' | 'personal'

let workspace_path = '~/workspace' | path expand
let worktrees_path =  $workspace_path | path join 'worktrees';

# https://matthiasportzel.com/brewfile/
def bbic [] {
  brew update
  # brew bundle install --cleanup --file=~/workspace/dotfiles/brewfile.work.rb
  # brew bundle install --cleanup --file=~/workspace/dotfiles/brewfile.home.rb
  brew upgrade
}

def start-feature [feature_name: string, --dry (-d)] {
  let repo_name: string = pwd | path basename;
  mut branch_name = $feature_name;
  let folder = ($worktrees_path | path join $"($feature_name)--($repo_name)");

  if $env.COMPUTER_TYPE == 'work' {
    $branch_name = $"users/maburson/($branch_name)";
  }

  let command = $"git worktree add -b ($branch_name) ($folder)"

  print $command;

  if $dry == false {
    nu -e $command
    code $folder;
  }
}
