# Copilot agent / CI shells need a POSIX shell (bash-style &&, ||, export, etc.).
# The agent's terminal sets COPILOT_AGENT / AI_AGENT; hand off to zsh before any
# nushell-specific setup runs. Interactive user terminals lack these vars and stay in nushell.
if ($env.COPILOT_AGENT? | is-not-empty) or ($env.AI_AGENT? | is-not-empty) {
    exec /bin/zsh -l
}

# See https://www.nushell.sh/book/configuration.html
#
# This file is loaded after env.nu and before login.nu
#
# You can open this file in your default editor using:
# config nu

$env.config.show_banner = false
$env.config.buffer_editor = 'code'

$env.path ++= ['/usr/local/bin', '/opt/homebrew/bin']

$env.PROMPT_COMMAND_RIGHT = ""

$env.PROMPT_COMMAND = {|| (echo $env.PWD | split row  "/" | last) }
$env.PROMPT_INDICATOR = ' % '

$env.computer_type = 'home' # 'work' | 'home'

let workspace_path = '~/workspace' | path expand
let worktrees_path =  $workspace_path | path join 'worktrees';
let dotfiles_path = $workspace_path | path join 'dotfiles';

# https://matthiasportzel.com/brewfile/
def _bbic [--cleanup (-c)] {
  let path = $env.brewfile_path? | default $dotfiles_path | path join $"brewfile.home.rb";
  print $"--file=(_brewfile_path)"
  brew update
  brew bundle install --file=(_brewfile_path) ...(if $cleanup { [--cleanup --force] } else { [] })
  brew upgrade
}

def _new_ts_project [] {
  asdf set nodejs 24.11.1
  yarn init -2
  "nodeLinker: node-modules\n" | save --force .yarnrc.yml
  yarn
  yarn add -D typescript @tsconfig/node24 prettier @types/node@24
  echo `{
    "semi": true,
    "trailingComma": "all",
    "singleQuote": true
  }
  ` | save --force .prettierrc
  echo `{
    "$schema": "https://www.schemastore.org/tsconfig",
    "extends": "@tsconfig/node24",
    "compilerOptions": {
      "noEmit": true,
      "rewriteRelativeImportExtensions": true,
      "erasableSyntaxOnly": true,
      "verbatimModuleSyntax": true
    }
  }
  ` | save --force tsconfig.json
  echo `.yarn` | save --force .prettierignore
  open ./package.json
    | upsert scripts.format 'prettier --write --ignore-unknown .'
    | save --force ./package.json
  yarn format
}

def _main-git-branch [] {
  git branch -r
    | lines
    | where ($it | str trim | str starts-with 'origin/HEAD')
    | first
    | parse '{_}/{_} -> {_}/{main_branch}'
    | first
    | get main_branch
}

def _run-worktree-hook [repo_name: string, folder: string] {
  let hooks = $env.worktree_hooks? | default {};
  if ($repo_name in $hooks) {
    cd $folder;
    do ($hooks | get $repo_name)
  }
}

def _start-feature [feature_name: string, --dry (-d), --from-current (-c)] {
  let repo_name: string = git config --get remote.origin.url | path basename;
  mut branch_name = $feature_name;
  let folder = ($worktrees_path | path join $"($feature_name)--($repo_name)");

  if $env.computer_type == 'work' {
    $branch_name = $"users/maburson/($branch_name)";
  }

  let main_git_branch = if $from_current {
    git branch --show-current
  } else {
    _main-git-branch
  }

  let command = $"git worktree add -b ($branch_name) ($folder) ($main_git_branch)" 

  print $command;

  if $dry == false {
    # nu -e $command |
    git worktree add -b $branch_name $folder $main_git_branch
    _run-worktree-hook $repo_name $folder
    code $folder
  } else {
    print { "repo_name": $repo_name, "branch_name": $branch_name, "folder": $folder, "main_git_branch": $main_git_branch}
  }
}

def _wto [] {
  ls $worktrees_path | each {|folder| $folder.name | path basename }
}

def _wt [branch?: string@_wto, --all (-a)] {
  if $all and ($branch != null) {
    print -e "Pass either a branch or --all, not both"
  } else if $all {
    _wto | each {|b| code ($worktrees_path | path join $b) }
  } else if ($branch != null) {
    code ($worktrees_path | path join $branch)
  } else {
    print -e "Pass a branch name or --all"
  }
}

# https://github.com/Schniz/fnm/issues/463#issuecomment-4381417804
if not (which fnm | is-empty) {
    ^fnm env --json | from json | load-env

    $env.path = $env.path | prepend ($env.FNM_MULTISHELL_PATH | path join (if $nu.os-info.name == 'windows' {''} else {'bin'}))
    $env.config.hooks.env_change.PWD = (
        $env.config.hooks.env_change.PWD? | append {
            condition: {|| ['.nvmrc' '.node-version', 'package.json'] | any {|el| $el | path exists}}
            code: {|| ^fnm use --install-if-missing --silent-if-unchanged}
        }
    )
}