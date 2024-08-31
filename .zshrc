. "$HOME/.asdf/asdf.sh"

## asdf

# append completions to fpath
fpath=(${ASDF_DIR}/completions $fpath)
# initialise completions with ZSH's compinit
autoload -Uz compinit && compinit
export ASDF_NODEJS_LEGACY_FILE_DYNAMIC_STRATEGY=latest_installed
