
# See https://www.nushell.sh/book/configuration.html
#
# This file is loaded after env.nu and before login.nu
#
# You can open this file in your default editor using:
# config nu

$env.config.show_banner = false
$env.config.buffer_editor = "code"

$env.VOLTA_HOME = "~/.volta"

$env.path ++= [$"($env.VOLTA_HOME)/bin"]

$env.PROMPT_COMMAND_RIGHT = ""

$env.PROMPT_COMMAND = {||  (echo $env.PWD | split row  "/" | last) }
$env.PROMPT_INDICATOR = ' % '