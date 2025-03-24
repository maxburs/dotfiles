
# Path configuration here instad of nushell config so binaries are available
# everywhere
PATH+=":/usr/local/bin:/opt/homebrew/bin"

## asdf

# . "$HOME/.asdf/asdf.sh"
# append completions to fpath
# fpath=(${ASDF_DIR}/completions $fpath)
# export ASDF_NODEJS_LEGACY_FILE_DYNAMIC_STRATEGY=latest_installed

# initialize completions with ZSH's compinit
autoload -Uz compinit && compinit

## Volta

export VOLTA_HOME="$HOME/.volta"

PATH+=":$VOLTA_HOME/bin"

precmd() {
  local EXIT="$?"

  PS1="%1~"

  if [ $EXIT != 0 ]; then
    PS1+="%{%F{red}%}[${EXIT}]%{%f%}"
  fi

  PS1+="\$ "
}
