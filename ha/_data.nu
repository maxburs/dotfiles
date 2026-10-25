# Downloaded data: the add-ons' logs, which the other commands read by default,
# and the Matter devices' names. data/ is gitignored.

const DATA = (path self . | path join data)
export const BORDER_ROUTER_LOG = ($DATA | path join border-router.log)
export const MATTER_LOG = ($DATA | path join matter.log)

# Home Assistant's names for Matter nodes, saved next to the Matter log: a
# list of {node, name}.
export const NODE_NAMES = 'matter-nodes.json'

const host = 'ha-yellow'

# Download the border router's and Matter Server's logs, and the Matter
# devices' names, from Home Assistant into data/, replacing the last download.
# Runs the `ha` CLI over ssh, so the host needs it, as the Terminal & SSH
# add-on has.
export def download [
  --logs: int,
  --logs-border-router = 10000,
  --logs-matter-server = 50_000,
]: nothing -> table {
  mkdir $DATA
  let logs = [
    [app lines path];
    [core_openthread_border_router ($logs | default $logs_border_router) $BORDER_ROUTER_LOG]
    [core_matter_server ($logs | default $logs_matter_server) $MATTER_LOG]
  ]
  | each {|log|
      let text = ssh-output $host $"ha apps logs ($log.app) --lines ($log.lines)"
      $text | ansi strip | save --force $log.path
      {file: $log.path, saved: $"($text | lines | length) lines"}
    }

  let names_path = $MATTER_LOG | path dirname | path join $NODE_NAMES
  let names = ssh-output $host 'cat /config/.storage/core.device_registry' | from json | matter-node-names
  $names | to json | save --force $names_path
  $logs | append {file: $names_path, saved: $"($names | length) Matter devices' names"}
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
