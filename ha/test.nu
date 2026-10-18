# test.nu — tests for the ha module, through its commands, with small made-up
# logs.
# Run with:  nu ~/workspace/dotfiles/ha/test.nu

# The expected times are Los Angeles times across its 2026 DST change, so run
# in that time zone whatever this machine's is.
const SELF = path self
if $env.TZ? != 'America/Los_Angeles' {
  with-env {TZ: 'America/Los_Angeles'} { ^$nu.current-exe $SELF }
  exit $env.LAST_EXIT_CODE
}

const HERE = path self .
use $HERE

$env.TESTS_PASSED = 0
$env.TESTS_FAILED = 0

def --env check [actual, expected, name: string]: nothing -> nothing {
  if $actual == $expected {
    print $"  ok   ($name)"
    $env.TESTS_PASSED += 1
  } else {
    print $"  FAIL ($name):\n    expected ($expected | to nuon)\n    got      ($actual | to nuon)"
    $env.TESTS_FAILED += 1
  }
}

let workdir = mktemp -d

try {
  # otbr-agent was already running when this log starts, so the first run's
  # times are counted back from the restart. The restart's last error is after
  # the DST change, and the indented line continues the failed send.
  let border_router_log = $workdir | path join border-router.txt
  [
    '1d.00:00:00.000 [W] P-RadioSpinel-: Handle transmit done failed: ChannelAccessFailure'
    '2d.00:00:00.000 [N] Mle-----------: Role router -> leader'
    '2026-10-31 12:00:00 homeassistant zigpy.serial[234] DEBUG Connection lost: None'
    '[12:00:00] INFO: Starting otbr-agent...'
    '00:00:00.000 [C] P-RadioSpinel-: RCP => [C] Platform------: Reset info: 0x3 (EXT)'
    '13:59:59.000 [W] P-RadioSpinel-: Handle transmit done failed: ChannelAccessFailure'
    '3d.00:00:00.000 [N] MeshForwarder-: Failed to send IPv6 UDP msg, error:NoAck, prio:low'
    '3d.00:00:00.000 [N] MeshForwarder-:     dst:[fd0b::1]:5540'
  ] | str join "\n" | save $border_router_log

  let caf = 'Handle transmit done failed: ChannelAccessFailure'
  check (ha border-router errors $border_router_log) [
    {time: '2026-10-30 Fri 12:00:00', level: W, module: P-RadioSpinel, message: $caf}
    {time: '2026-11-01 Sun 01:59:59', level: W, module: P-RadioSpinel, message: $caf}
    {time: '2026-11-03 Tue 11:00:00', level: N, module: MeshForwarder, message: 'Failed to send IPv6 UDP msg, error:NoAck, prio:low'}
  ] "ha border-router errors: estimated first run, DST, continuation lines"
  check (ha border-router errors $border_router_log --daily) [
    {date: '2026-10-30 Fri', ChannelAccessFailure: 1, NoAck: 0, total: 1}
    {date: '2026-10-31 Sat', ChannelAccessFailure: 0, NoAck: 0, total: 0}
    {date: '2026-11-01 Sun', ChannelAccessFailure: 1, NoAck: 0, total: 1}
    {date: '2026-11-02 Mon', ChannelAccessFailure: 0, NoAck: 0, total: 0}
    {date: '2026-11-03 Tue', ChannelAccessFailure: 0, NoAck: 1, total: 1}
  ] "ha border-router errors --daily: a column per kind, days without errors"
  check (ha border-router errors $border_router_log --since '2026-11-01 12:00' | get time) ['2026-11-03 Tue 11:00:00'] "ha border-router errors --since"

  # Node 0xa is removed while unavailable, 0x12 (18) recovers twice (once
  # without a subscription timeout first), and 7 never comes back.
  let matter_log = $workdir | path join matter.txt
  [
    '2026-10-01 10:00:00.000 INFO   ClientSubscription   Subscription aa to peer @1:a timed out after 1m 41s'
    '2026-10-01 10:03:00.000 WARN   Controller~ndHandler Node @1:a offline grace period expired, marking unavailable'
    '2026-10-01 11:00:00.000 INFO   Peer                 Removing @1:a'
    '2026-10-01 12:00:00.000 INFO   ClientSubscription   Subscription bb to peer @1:12 timed out after 15m 38s'
    '2026-10-01 12:03:00.000 WARN   Controller~ndHandler Node @1:12 offline grace period expired, marking unavailable'
    '2026-10-01 12:30:00.000 INFO   WebSocketC~erHandler [2] Node @1:12 availability changed to true'
    '2026-10-01 12:30:00.000 NOTICE Controller~ndHandler Node @1:12 availability changed to true (state: Connected)'
    '2026-10-03 08:00:00.000 WARN   Controller~ndHandler Node @1:12 offline grace period expired, marking unavailable'
    '2026-10-03 09:00:00.000 NOTICE Controller~ndHandler Node @1:12 availability changed to true (state: Connected)'
    '2026-10-04 06:00:00.000 WARN   Controller~ndHandler Node @1:7 offline grace period expired, marking unavailable'
    '2026-10-05 12:00:00.000 INFO   ClientInteraction    Invoke » @1:6•9c02⇵b86f 1.onOff.on with (no payload)'
  ] | str join "\n" | save $matter_log
  # `ha download` saves names next to the log; only node 18's is known here.
  [{node: 18, name: 'Bedroom lightswitch'}] | to json | save ($workdir | path join matter-nodes.json)

  let switch = 'Bedroom lightswitch'
  check (ha matter disconnects $matter_log) [
    {node: 10, name: null, last_heard: '2026-10-01 Thu 09:58:19', unavailable: '2026-10-01 Thu 10:03:00', available: removed, down: 57min}
    {node: 18, name: $switch, last_heard: '2026-10-01 Thu 11:44:22', unavailable: '2026-10-01 Thu 12:03:00', available: '2026-10-01 Thu 12:30:00', down: 27min}
    {node: 18, name: $switch, last_heard: null, unavailable: '2026-10-03 Sat 08:00:00', available: '2026-10-03 Sat 09:00:00', down: 1hr}
    {node: 7, name: null, last_heard: null, unavailable: '2026-10-04 Sun 06:00:00', available: 'still unavailable', down: 30hr}
  ] "ha matter disconnects: names, last heard, removed, still unavailable"
  check (ha matter disconnects $matter_log --daily) [
    {date: '2026-10-01 Thu', 'node 7': 0, 'node 10': 1, 'node 18': 1, total: 2}
    {date: '2026-10-02 Fri', 'node 7': 0, 'node 10': 0, 'node 18': 0, total: 0}
    {date: '2026-10-03 Sat', 'node 7': 0, 'node 10': 0, 'node 18': 1, total: 1}
    {date: '2026-10-04 Sun', 'node 7': 1, 'node 10': 0, 'node 18': 0, total: 1}
    {date: '2026-10-05 Mon', 'node 7': 0, 'node 10': 0, 'node 18': 0, total: 0}
  ] "ha matter disconnects --daily: a column per node, days without outages"

  let unavailable_7 = 'unavailable since 2026-10-04 Sun 06:00:00'
  let removed_10 = 'removed 2026-10-01 Thu 11:00:00'
  check (ha matter downtime $matter_log) [
    {from: '2026-10-01 Thu', to: '2026-10-03 Sat', down: 144min, nodes: [
      {node: 10, name: null, outages: 1, down: 57min, note: $removed_10}
      {node: 18, name: $switch, outages: 2, down: 87min, note: null}
    ]}
    {from: '2026-10-04 Sun', to: '2026-10-05 Mon', down: 30hr, nodes: [
      {node: 7, name: null, outages: 1, down: 30hr, note: $unavailable_7}
    ]}
  ] "ha matter downtime: weeks from Sunday, cut to the log, with total downtime"

  # Periods are local days: Sunday, Nov 1, when DST ends, is 25 hours long.
  # Node 1's outage began on the 31st, so later days count its downtime but
  # not the outage.
  let dst_log = $workdir | path join dst.txt
  [
    '2026-10-31 12:00:00.000 WARN   Controller~ndHandler Node @1:1 offline grace period expired, marking unavailable'
    '2026-11-02 12:00:00.000 NOTICE Controller~ndHandler Node @1:1 availability changed to true (state: Connected)'
  ] | str join "\n" | save $dst_log
  check (ha matter downtime $dst_log --bin 1day | each {|p| {from: $p.from, outages: $p.nodes.0.outages, down: $p.nodes.0.down} }) [
    {from: '2026-10-31 Sat', outages: 1, down: 12hr}
    {from: '2026-11-01 Sun', outages: 0, down: 25hr}
    {from: '2026-11-02 Mon', outages: 0, down: 12hr}
  ] "ha matter downtime --bin 1day: local days, across a DST change"
  check (try { ha matter downtime $matter_log --bin 36hr; 'no error' } catch {|e| $e.msg }) '--bin must be a whole number of days' "ha matter downtime --bin: whole days only"
} catch { |err|
  # Unexpected error: clean up, then report it as a failure.
  rm -rf $workdir
  print -e $err.rendered
  exit 2
}

rm -rf $workdir
print $"\n($env.TESTS_PASSED) passed, ($env.TESTS_FAILED) failed"
if $env.TESTS_FAILED > 0 { exit 1 }
