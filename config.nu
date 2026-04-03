
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

$env.ASDF_NODEJS_AUTO_ENABLE_COREPACK = 'true'
$env.ASDF_NODEJS_LEGACY_FILE_DYNAMIC_STRATEGY = 'latest_available';
$env.ASDF_DATA_DIR = '~/.asdf' | path expand
$env.path ++= [$"($env.ASDF_DATA_DIR)/shims" ]
source ~/.asdf/completions/nushell.nu

$env.PROMPT_COMMAND_RIGHT = ""

$env.PROMPT_COMMAND = {||  (echo $env.PWD | split row  "/" | last) }
$env.PROMPT_INDICATOR = ' % '

def bbic [] {
  brew update
  # brew bundle install --cleanup --file=~/workspace/dotfiles/brewfile.work.rb
  # brew bundle install --cleanup --file=~/workspace/dotfiles/brewfile.home.rb
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
