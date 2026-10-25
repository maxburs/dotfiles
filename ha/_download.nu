# `ha download`: add-ons' logs and the Matter devices' names, from Home
# Assistant into data/ (gitignored), where the other commands read them by
# default.

const DATA = (path self . | path join data)

# Each add-on's log is saved as data/<its slug>.log.
export const BORDER_ROUTER_LOG = ($DATA | path join core_openthread_border_router.log)
export const MATTER_LOG = ($DATA | path join core_matter_server.log)

# Home Assistant's names for Matter nodes, saved next to the Matter log: a
# list of {node, name}.
export const NODE_NAMES = 'matter-nodes.json'

const host = 'ha-yellow'

# The add-ons `download` gets logs from, by their slugs in Home Assistant, and
# how many of their last lines it gets unless given --logs.
const APPS = [
  [app lines path];
  [core_openthread_border_router 10_000 $BORDER_ROUTER_LOG]
  [core_matter_server 50_000 $MATTER_LOG]
]

# Download add-ons' logs from Home Assistant into data/, replacing the last
# download: the border router's and Matter Server's, or just the ones named.
# The Matter devices' names come along with Matter Server's log. Runs the `ha`
# CLI over ssh, so the host needs it, as the Terminal & SSH add-on has.
export def download [
  ...apps: string@app-names  # add-ons' slugs (default: all of them)
  --logs: int                # lines to download of each log (default: 10000 of the border router's, 50000 of Matter Server's)
]: nothing -> table {
  let apps = if ($apps | is-empty) { $APPS.app } else { $apps | uniq }
  # All checked first, so a typo doesn't leave a partial download.
  for app in $apps {
    if $app not-in $APPS.app {
      error make --unspanned {
        msg: $"Unknown add-on: ($app)"
        help: $"Download any of: ($APPS.app | str join ', ')"
      }
    }
  }

  mkdir $DATA
  let saved = $APPS | where app in $apps | each {|log|
    let text = ssh-output $host $"ha apps logs ($log.app) --lines ($logs | default $log.lines)"
    $text | ansi strip | save --force $log.path
    {file: $log.path, saved: $"($text | lines | length) lines"}
  }
  if ($MATTER_LOG not-in $saved.file) { return $saved }

  let names_path = $MATTER_LOG | path dirname | path join $NODE_NAMES
  let names = ssh-output $host 'cat /config/.storage/core.device_registry' | from json | matter-node-names
  $names | to json | save --force $names_path
  $saved | append {file: $names_path, saved: $"($names | length) Matter devices' names"}
}

def app-names []: nothing -> list<string> {
  $APPS.app
}

# What `command` prints on `host`, or an error with what it printed to stderr.
def ssh-output [host: string, command: string]: nothing -> string {
  let result = ^ssh $host $command | complete
  if $result.exit_code != 0 {
    error make --unspanned {
      msg: $"`ssh ($host) '($command)'` failed: ($result.stderr | str trim)"
      help: $"The last download, if any, is still in ($DATA)."
    }
  }
  $result.stdout
}

# Each Matter node's name, from Home Assistant's device registry: the name it
# was given there, or else the device's own. The registry identifies a node as
# `deviceid_<fabric>-<node ID in hex>-MatterNodeDevice`.
def matter-node-names []: record -> table {
  $in.data.devices
  | each {|device|
      let ids = $device.identifiers
        | where {|id| $id.0 == 'matter' }
        | each {|id| $id.1 | parse --regex '^deviceid_[0-9A-F]+-(?<node>[0-9A-F]+)-MatterNodeDevice$' }
        | flatten
      if ($ids | is-not-empty) {
        {node: ($ids.0.node | into int --radix 16), name: ($device.name_by_user | default $device.name)}
      }
    }
  | sort-by node
}
