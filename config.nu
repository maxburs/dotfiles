
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

$env.computer_type = 'home' # 'work' | 'home'

let workspace_path = '~/workspace' | path expand
let worktrees_path =  $workspace_path | path join 'worktrees';
let dotfiles_path = $workspace_path | path join 'dotfiles';

# https://matthiasportzel.com/brewfile/
def bbic [] {
  brew update
  brew bundle install --cleanup --file=($dotfiles_path | path join $"brewfile.($env.computer_type).rb")
  brew upgrade
}

def backup-nu-config [] {
  mut config = open $nu.config-path;
  $config | save --force `~/OneDrive - Microsoft/config.nu`;
  let deliminator = '## -- Local modifications --';
  $config = $config | split row $"\n($deliminator)" | first | str join $"\n($deliminator)\n";
  $config | save --force ($dotfiles_path | path join 'config.nu');
}

def main-git-branch [] {
  git branch -r
    | lines
    | where ($it | str trim | str starts-with 'origin/HEAD')
    | first
    | parse '{_}/{_} -> {_}/{main_branch}'
    | first
    | get main_branch
}

def start-feature [feature_name: string, --dry (-d)] {
  let repo_name: string = pwd | path basename;
  mut branch_name = $feature_name;
  let folder = ($worktrees_path | path join $"($feature_name)--($repo_name)");

  if $env.computer_type == 'work' {
    $branch_name = $"users/maburson/($branch_name)";
  }

  let command = $"git worktree add -b ($branch_name) ($folder) (main-git-branch)" 

  print $command;

  if $dry == false {
    nu -e $command
    code $folder
  }
}
