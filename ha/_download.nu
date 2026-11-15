# `ha download`: Home Assistant's logs, its own and its add-ons', and the
# Matter devices' names, into data/ (gitignored), where the other commands
# read them by default.

const DATA = (path self . | path join data)

# Each log is saved as data/<provider>.log.
export const BORDER_ROUTER_LOG = ($DATA | path join core_openthread_border_router.log)
export const MATTER_LOG = ($DATA | path join core_matter_server.log)

# Home Assistant's names for Matter nodes, saved next to the Matter log: a
# list of {node, name}.
export const NODE_NAMES = 'matter-nodes.json'

const host = 'ha-yellow'

# The logs `download` can get, as Settings > System > Logs lists them: a part
# of Home Assistant, or an add-on by its slug. `lines` is how many of the last
# lines it gets unless given --logs; they come at about 800 a second.
const PROVIDERS = [
  [provider                      title                      lines  command];
  [core                          'Home Assistant Core'      10_000 'ha core logs']
  [supervisor                    Supervisor                 10_000 'ha supervisor logs']
  [host                          Host                       10_000 'ha host logs']
  [dns                           DNS                        10_000 'ha dns logs']
  [audio                         Audio                      10_000 'ha audio logs']
  [multicast                     Multicast                  10_000 'ha multicast logs']
  [core_matter_server            'Matter Server'            50_000 'ha apps logs core_matter_server']
  [core_openthread_border_router 'OpenThread Border Router' 10_000 'ha apps logs core_openthread_border_router']
  [core_ssh                      'Terminal & SSH'           10_000 'ha apps logs core_ssh']
]

# What `download` gets unless told which logs: the ones the other commands read.
const DEFAULT_PROVIDERS = [core_openthread_border_router core_matter_server]

# Download logs from Home Assistant into data/<provider>.log, replacing the
# last download: the border router's and Matter Server's, or the ones named,
# any that Settings > System > Logs lists. The Matter devices' names come
# along with Matter Server's log. Runs the `ha` CLI over ssh, so the host
# needs it, as the Terminal & SSH add-on has.
export def download [
  ...providers: string@provider-names  # which logs (default: the border router's and Matter Server's)
  --logs: int                          # lines to download of each log (default: 50000 of Matter Server's, else 10000)
]: nothing -> table {
  let providers = if ($providers | is-empty) { $DEFAULT_PROVIDERS } else { $providers | uniq }
  # All checked first, so a typo doesn't leave a partial download.
  for provider in $providers {
    if $provider not-in $PROVIDERS.provider {
      error make --unspanned {
        msg: $"Unknown log: ($provider)"
        help: $"Download any of: ($PROVIDERS.provider | str join ', ')"
      }
    }
  }

  mkdir $DATA
  let saved = $PROVIDERS | where provider in $providers | each {|log|
    let path = $DATA | path join $"($log.provider).log"
    let text = ssh-output $host $"($log.command) --lines ($logs | default $log.lines)"
    $text | ansi strip | save --force $path
    {file: $path, saved: $"($text | lines | length) lines"}
  }
  if ($MATTER_LOG not-in $saved.file) { return $saved }

  let names_path = $MATTER_LOG | path dirname | path join $NODE_NAMES
  let names = ssh-output $host 'cat /config/.storage/core.device_registry' | from json | matter-node-names
  $names | to json | save --force $names_path
  $saved | append {file: $names_path, saved: $"($names | length) Matter devices' names"}
}

# Tab completions for download's logs, described as Settings > System > Logs
# names them.
def provider-names []: nothing -> list<record> {
  $PROVIDERS | each {|p| {value: $p.provider, description: $p.title} }
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
