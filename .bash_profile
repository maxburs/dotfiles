# shellcheck shell=bash

PROMPT_COMMAND=__prompt_command

__prompt_command() {
  local EXIT="$?"

  PS1="\W"


  local RCol='\[\e[0m\]'
  local Red='\[\e[0;31m\]'

  if [ $EXIT != 0 ]; then
    PS1+="${Red}[${EXIT}]${RCol}"
  fi

  PS1+="\$ "
}
