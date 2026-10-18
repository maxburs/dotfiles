# The OpenThread Border Router add-on's log: its errors, with their local times.
#
# otbr-agent stamps OpenThread's log lines, the ones read here, with its uptime
# (`HH:MM:SS.mmm`, or `<days>d.HH:MM:SS.mmm` after the first day) rather than
# the time. Each time the add-on starts, though, the lines logged just before
# otbr-agent starts carry a full timestamp (`2026-09-15 05:10:33 homeassistant
# ...`), so uptimes are added to the last of those. An uptime lower than the one
# before it means otbr-agent restarted. Home Assistant runs add-ons in its
# configured time zone, which is assumed to be this machine's.

use _data.nu [BORDER_ROUTER_LOG]
use _time.nu [TIME_FORMAT count-by-day]

# A full timestamp, or an otbr-agent line: uptime, level, module (padded with
# dashes), and message.
const LINE_PATTERN = (
  '^(?:(?<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})'
  + '|(?:(?<days>\d+)d\.)?(?<hours>\d{2}):(?<minutes>\d{2}):(?<seconds>\d{2})\.(?<ms>\d{3})'
  + ' \[(?<level>[A-Z])\] (?<module>[^:]+?)-*: (?<message>.*))'
)

# otbr-agent messages that count as errors. The rest (role changes, TREL peer
# address updates, routes, ...) are informational.
const ERROR_PATTERN = '(?i)fail|error'

# An error's kind, for --daily: the `error:` field of a failed send, or the
# reason after "failed: ". E.g. NoAck or ChannelAccessFailure.
const KIND_PATTERN = '(?:error:|failed: )(?<kind>\w+)'

# List the border router's errors with their local times, from the downloaded
# log or the one at `path`.
export def errors [
  path: path = $BORDER_ROUTER_LOG
  --since: string  # only errors from this local time on, e.g. 2026-10-10 or '2026-10-10 18:00'
  --daily          # count errors per day, by kind, instead of listing them
]: nothing -> table {
  let since = if $since != null { $since | into datetime }
  let lines = parse-log $path
  let runs = agent-runs $lines (ls $path | get 0.modified)
  if ($runs | is-empty) {
    error make --unspanned {msg: $"No otbr-agent lines in ($path)"}
  }

  let timed = $lines
    | enumerate
    | where item.uptime != null
    | each {|line|
        let run = $runs | where first <= $line.index | last
        $line.item
        | insert time ($run.started + $line.item.uptime | to-local)
        | insert estimate $run.estimate
      }
  # Indented lines continue the line before, e.g. a failed send's src and dst.
  let errors = $timed | where {|l| (
    $l.message =~ $ERROR_PATTERN
    and not ($l.message starts-with ' ')
    and ($since == null or $l.time >= $since)
  )}

  for estimate in ($errors | get -o estimate | compact | uniq) {
    print -e $"Note: ($estimate)"
  }
  if $daily {
    let rows = $errors | each {|e| {
      time: $e.time
      column: ($e.message | parse --regex $KIND_PATTERN | get -o 0.kind | default 'other')
    } }
    # The most common kinds first, but 'other' last.
    let kinds = $rows | each { $in.column } | uniq --count | sort-by count --reverse | each { $in.value }
    let kinds = ($kinds | where $it != 'other') ++ ($kinds | where $it == 'other')
    count-by-day $rows $kinds ($since | default ($timed | first).time) ($timed | last).time
  } else {
    $errors | select time level module message | update time { format date $TIME_FORMAT }
  }
}

# The log's timestamped lines, in order: full timestamps, logged while the
# add-on starts, and otbr-agent's lines with their uptime.
def parse-log [path: path]: nothing -> table {
  open --raw $path
  | lines
  | ansi strip
  | parse --regex $LINE_PATTERN
  | each {|l|
      let uptime = if $l.timestamp == null {(
        ($l.days | default 0 | into int) * 1day
        + ($l.hours | into int) * 1hr
        + ($l.minutes | into int) * 1min
        + ($l.seconds | into int) * 1sec
        + ($l.ms | into int) * 1ms
      )}
      {
        timestamp: (if $l.timestamp != null { $l.timestamp | into datetime })
        uptime: $uptime
        level: $l.level
        module: $l.module
        message: $l.message
      }
    }
}

# otbr-agent's runs, in order: the index in `lines` of each one's first line,
# and when it started. A run begins at the first otbr-agent line and wherever
# the uptime drops, and started at the last full timestamp before that line.
# Without one (otbr-agent was already running when the log begins), the start
# is estimated from when the run ended, the next run's start or else when the
# log file was saved, by assuming the run's last line was logged right then.
def agent-runs [lines: table, saved: datetime]: nothing -> table {
  mut starts = []
  # The last full timestamp since the previous otbr-agent line.
  mut timestamp: oneof<datetime, nothing> = null
  mut uptime: oneof<duration, nothing> = null
  for line in ($lines | enumerate) {
    if $line.item.timestamp != null {
      $timestamp = $line.item.timestamp
    } else {
      if $uptime == null or $line.item.uptime < $uptime {
        $starts = $starts | append {first: $line.index, timestamp: $timestamp}
      }
      $timestamp = null
      $uptime = $line.item.uptime
    }
  }

  # Backwards, so each run's end (the next run's start) is known.
  mut end = {time: $saved, event: 'the log file was saved'}
  mut runs = []
  for start in ($starts | enumerate | reverse) {
    let next_first = $starts | get -o ($start.index + 1) | get -o first | default ($lines | length)
    let last_uptime = $lines | slice $start.item.first..<$next_first | where uptime != null | last | get uptime
    let run = if $start.item.timestamp != null {
      {first: $start.item.first, started: $start.item.timestamp, estimate: null}
    } else {
      let end_time = $end.time | to-local | format date $TIME_FORMAT
      {
        first: $start.item.first
        started: ($end.time - $last_uptime)
        estimate: (
          $"times before ($end_time) are estimates. The log doesn't show when otbr-agent "
          + $"started before then, so they assume its last line was logged just as ($end.event); "
          + "real times may be earlier."
        )
      }
    }
    $runs = $runs | prepend $run
    $end = {time: $run.started, event: 'it restarted'}
  }
  $runs
}

# The same instant in the local time zone. `date to-timezone local` uses
# today's UTC offset for every date, so it's an hour off across a DST change.
def to-local []: datetime -> datetime {
  into int | into datetime --timezone local
}
