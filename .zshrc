# Path configuration here instead of nushell config so binaries are available
# everywhere
PATH+=":/usr/local/bin:/opt/homebrew/bin"

# initialize completions with ZSH's compinit
autoload -Uz compinit && compinit

precmd() {
  local EXIT="$?"

  PS1="%1~"

  if [ $EXIT != 0 ]; then
    PS1+="%{%F{red}%}[${EXIT}]%{%f%}"
  fi

  PS1+="\$ "
}

# fnm: https://github.com/Schniz/fnm
eval "$(fnm env --use-on-cd --shell zsh)"
