# https://www.nushell.sh/book/configuration.html

# Copilot agent / CI shells need a POSIX shell (bash-style &&, ||, export, etc.).
# The agent's terminal sets COPILOT_AGENT / AI_AGENT; hand off to zsh before any
# nushell-specific setup runs. Interactive user terminals lack these vars and stay in nushell.
if ($env.COPILOT_AGENT? | is-not-empty) or ($env.AI_AGENT? | is-not-empty) {
    exec /bin/zsh -l
}

use std/assert
use std/util "path add"

$env.config.show_banner = false
$env.config.buffer_editor = ['code' '--wait']

# Rust/Cargo
source ("~/.cargo/env.nu" | path expand)

path add /usr/local/bin /opt/homebrew/bin

# Nix
use ./nix/nix-env.nu load-nix-env
try { load-nix-env } catch { |err| print -e $err.rendered }

# Prompt: the current folder (~ at home), then non-zero exit codes
$env.PROMPT_COMMAND_RIGHT = ""
$env.PROMPT_COMMAND = {||
  # path expand: $nu.home-dir has symlinks resolved, $env.PWD may not.
  let folder = if ($env.PWD | path expand) == ($nu.home-dir | path expand) {
    '~'
  } else if $env.PWD == '/' {
    '/'
  } else {
    $env.PWD | path basename
  }
  let failed = if $env.LAST_EXIT_CODE != 0 { $"(ansi red)[($env.LAST_EXIT_CODE)](ansi reset)" } else { '' }
  $folder + $failed
}
$env.PROMPT_INDICATOR = ' % '

# Per-machine settings, set in the local config.nu (`config nu`):
#   $env.computer_type   'home' (default) or 'work'; 'work' prefixes new branches with users/maburson/
#   $env.brewfile_path   Brewfile for _bbic and _brew-unmanaged; defaults to brewfile.home.rb here
#   $env.worktree_hooks  closures _start-feature runs in new worktrees, keyed by the origin URL's
#                        last segment: {dotfiles.git: {|| ... }}
$env.computer_type = $env.computer_type? | default 'home'

let workspace_path = '~/workspace' | path expand
let worktrees_path = $workspace_path | path join 'worktrees'
let dotfiles_path = $workspace_path | path join 'dotfiles'

# The Brewfile for _bbic and _brew-unmanaged.
def _brewfile [] {
  let path = $env.brewfile_path? | default ($dotfiles_path | path join 'brewfile.home.rb')
  if not ($path | path exists) {
    error make --unspanned {
      msg: $"Brewfile not found: ($path)"
      help: "Point $env.brewfile_path at your Brewfile (see the per-machine settings in config.nu)."
    }
  }
  $path
}

# https://matthiasportzel.com/brewfile/
def _bbic [] {
  let path = _brewfile
  print $"--file=($path)"
  brew update
  brew bundle install --file=($path)
  brew upgrade
}

# Installed packages the Brewfile doesn't list, i.e. what `brew bundle cleanup
# --force` would uninstall. The report's trailing `brew cleanup` section (old
# versions, caches) is left out.
def _brew-unmanaged [] {
  # Without --force this only reports, exiting 1 when something would be removed.
  let result = (HOMEBREW_NO_AUTO_UPDATE=1 ^brew bundle cleanup $"--file=(_brewfile)" | complete)
  let found = (
    $result.stdout
    | lines
    | take until { $in starts-with 'Would `brew cleanup`' or $in starts-with 'Run `brew bundle' }
    | reduce --fold {kind: null, rows: []} {|line, acc|
        # Section headers look like "Would uninstall formulae:" or "Would untap:".
        let header = ($line | parse --regex '^Would (?:uninstall )?(?<kind>.+):$')
        if ($header | is-not-empty) {
          $acc | update kind ($header.0.kind | str replace --regex '^untap$' 'taps')
        } else {
          assert ($acc.kind != null) $"Unexpected `brew bundle cleanup` output: ($line)"
          $acc | update rows { append {kind: $acc.kind, name: $line} }
        }
      }
    | get rows
  )
  if $result.exit_code != 0 and ($found | is-empty) {
    error make --unspanned {msg: $"brew bundle cleanup failed: ($result.stderr | str trim)"}
  }
  $found
}

def _new_ts_project [
  --node: string = '24'  # Node version to pin in .node-version (read by fnm): 24 means the newest 24.x
] {
  if $node !~ '^\d+(\.\d+){0,2}$' {
    error make {
      msg: "--node must be a version like 24, 24.11 or 24.11.1"
      label: {text: "not a version", span: (metadata $node).span}
    }
  }
  if (which fnm | is-empty) {
    error make --unspanned {msg: "fnm is not installed", help: "It's in brewfile.rb; install it with _bbic or `brew install fnm`."}
  }
  if ('package.json' | path exists) {
    error make --unspanned {msg: "package.json already exists", help: "Run this in a new, empty directory."}
  }
  let major = ($node | split row '.' | first)

  # --corepack-enabled gives a Node that fnm installs here corepack's yarn.
  fnm use --install-if-missing --corepack-enabled $node
  if (which yarn | is-empty) {
    error make --unspanned {msg: $"yarn isn't available for Node ($node)", help: "Run `corepack enable`, then run this again."}
  }
  $"($node)\n" | save --force .node-version
  yarn init -2
  "nodeLinker: node-modules\n" | save --force .yarnrc.yml
  yarn
  yarn add -D typescript $"@tsconfig/node($major)" prettier $"@types/node@($major)"
  {semi: true, trailingComma: 'all', singleQuote: true} | to json | save --force .prettierrc
  {
    '$schema': 'https://www.schemastore.org/tsconfig'
    extends: $"@tsconfig/node($major)"
    compilerOptions: {
      noEmit: true
      rewriteRelativeImportExtensions: true
      erasableSyntaxOnly: true
      verbatimModuleSyntax: true
    }
  } | to json | save --force tsconfig.json
  ".yarn\n" | save --force .prettierignore
  open package.json
    | upsert scripts.format 'prettier --write --ignore-unknown .'
    | save --force package.json
  yarn format
}

# origin's default branch (e.g. main), from origin/HEAD.
def _main-git-branch [] {
  let result = (git rev-parse --abbrev-ref origin/HEAD | complete)
  if $result.exit_code != 0 {
    error make --unspanned {
      msg: $"Can't resolve origin/HEAD: ($result.stderr | lines | first 1 | str join)"
      help: "If origin/HEAD isn't set, run `git remote set-head origin --auto`."
    }
  }
  let ref = ($result.stdout | str trim)
  assert ($ref starts-with 'origin/') $"origin/HEAD resolved to ($ref), not a branch under origin/"
  $ref | str replace 'origin/' ''
}

def _run-worktree-hook [repo_name: string, folder: string] {
  let hooks = $env.worktree_hooks? | default {}
  if ($repo_name in $hooks) {
    cd $folder
    do ($hooks | get $repo_name)
  }
}

def _start-feature [feature_name: string, --dry (-d), --from-current (-c)] {
  assert ($env.computer_type in ['home' 'work']) $"$env.computer_type must be 'home' or 'work', not ($env.computer_type | to nuon)"

  let origin = (git config --get remote.origin.url | complete)
  if $origin.exit_code != 0 {
    error make --unspanned {msg: "_start-feature needs a git repo with an origin remote"}
  }
  let repo_name = ($origin.stdout | str trim | path basename)

  let branch_name = if $env.computer_type == 'work' { $"users/maburson/($feature_name)" } else { $feature_name }
  # A '/' would nest the worktree folder, where _wto and _wt don't look.
  if ($feature_name | str contains '/') or (git check-ref-format --branch $branch_name | complete).exit_code != 0 {
    error make {
      msg: $"Invalid feature name: ($feature_name | to nuon)"
      label: {text: "must be a valid branch name, without '/'", span: (metadata $feature_name).span}
    }
  }
  let folder = ($worktrees_path | path join $"($feature_name)--($repo_name)")

  # Checked now, so a bad hook fails before the worktree is created.
  let hooks = $env.worktree_hooks? | default {}
  assert (($hooks | describe) starts-with 'record') $"$env.worktree_hooks must be a record, not ($hooks | describe)"
  let hook = ($hooks | get -o $repo_name)
  assert ($hook == null or ($hook | describe) == 'closure') $"$env.worktree_hooks.($repo_name) must be a closure, not ($hook | describe)"

  let main_git_branch = if $from_current {
    let current = (git branch --show-current)
    if ($current | is-empty) {
      error make {
        msg: "HEAD is detached, so there's no current branch to start from"
        label: {text: "needs a checked-out branch", span: (metadata $from_current).span}
      }
    }
    $current
  } else {
    _main-git-branch
  }

  let command = $"git worktree add -b ($branch_name) ($folder) ($main_git_branch)"

  print $command

  if $dry {
    print { "repo_name": $repo_name, "branch_name": $branch_name, "folder": $folder, "main_git_branch": $main_git_branch}
  } else {
    git worktree add -b $branch_name $folder $main_git_branch
    _run-worktree-hook $repo_name $folder
    code $folder
  }
}

def _wto [] {
  ls $worktrees_path | where type == dir | get name | path basename
}

def _wt [branch?: string@_wto, --all (-a)] {
  if $all and $branch != null {
    error make {
      msg: "Pass either a branch or --all, not both"
      labels: [{text: "either this", span: (metadata $branch).span} {text: "or this", span: (metadata $all).span}]
    }
  }
  if not $all and $branch == null {
    error make --unspanned {msg: "Pass a branch name or --all"}
  }
  if $branch != null and not ($worktrees_path | path join $branch | path exists) {
    error make {
      msg: $"No worktree named ($branch) in ($worktrees_path)"
      label: {text: "no such worktree", span: (metadata $branch).span}
    }
  }
  let folders = if $all { _wto } else { [$branch] }
  for folder in $folders {
    code ($worktrees_path | path join $folder)
  }
}

# https://github.com/Schniz/fnm/issues/463#issuecomment-4381417804
if (which fnm | is-not-empty) {
    ^fnm env --json | from json | load-env

    path add ($env.FNM_MULTISHELL_PATH | path join (if $nu.os-info.name == 'windows' {''} else {'bin'}))
    $env.config.hooks.env_change.PWD = (
        $env.config.hooks.env_change.PWD? | append {
            condition: {|| ['.nvmrc' '.node-version' 'package.json'] | any {|el| $el | path exists}}
            code: {|| ^fnm use --install-if-missing --silent-if-unchanged}
        }
    )
}