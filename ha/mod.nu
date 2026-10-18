# ha — read the logs of Home Assistant's OpenThread Border Router and Matter
# Server add-ons, to see how the Thread network is doing.
#
# Load it when you need it (config.nu puts this repo on NU_LIB_DIRS, so this
# works from any folder), then type `ha` and press tab to list its commands.
# Leave off the `*` in `use ha *`, which would drop their `ha` prefix.
#
#   use ha
#   ha download                               # logs and device names, into ha/data/
#   ha matter downtime                        # each node's outages and downtime, by week
#   ha matter disconnects --since 2026-10-11  # each outage
#   ha border-router errors --daily           # the border router's errors, by day
#
# The commands read the downloaded data unless given a log's path, and
# `help ha <command>` shows a command's flags. Tests: nu ha/test.nu

export use _data.nu download
export use border-router.nu
export use matter.nu
