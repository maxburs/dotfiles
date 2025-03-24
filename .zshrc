PATH+=":/usr/local/bin:/opt/homebrew/bin"

## asdf

# https://asdf-vm.com/guide/getting-started.html#_2-configure-asdf

export ASDF_DATA_DIR="$HOME/.asdf"

PATH+=":$ASDF_DATA_DIR/shims"

# https://github.com/asdf-vm/asdf-nodejs
export ASDF_NODEJS_LEGACY_FILE_DYNAMIC_STRATEGY=latest_installed

# initialize completions with ZSH's compinit
autoload -Uz compinit && compinit

## Volta

# export VOLTA_HOME="$HOME/.volta"

# PATH+=":$VOLTA_HOME/bin"

precmd() {
  local EXIT="$?"

  PS1="%1~"

  if [ $EXIT != 0 ]; then
    PS1+="%{%F{red}%}[${EXIT}]%{%f%}"
  fi

  PS1+="\$ "
}

export AZURE_DEVOPS_PAT="5LVJ0WMga5V0EVn3LZeDlWyt8xm7I4vFB4TlLAwUYCmTl10DNGAhJQQJ99BCACAAAAAAArohAAASAZDO4UJ0"
