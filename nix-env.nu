# nix-env.nu — load Nix's environment into Nushell.
#
# Nix ships profile scripts only for POSIX shells and fish, so Nushell cannot
# source them directly (upstream: https://github.com/NixOS/nix/issues/9813;
# delete this module once Nix ships a Nushell script). Instead, bash snapshots
# its exported environment, sources the script, and snapshots it again; the
# variables the script added, changed, or unset are then applied to Nushell,
# with PATH converted to a list.
#
# Only exported environment variables cross over. Shell functions, aliases,
# options, traps, and the working directory stay behind in bash.
#
# Usage, from config.nu:
#
#   use ./nix-env.nu load-nix-env
#   load-nix-env
#
# Optionally pass a specific script. Unlike the default search, an explicit
# path must be a readable file; it never silently falls back to another one:
#
#   load-nix-env /nix/var/nix/profiles/default/etc/profile.d/nix.sh
#
# parse-env0 and resolve-nix-script are exported for the tests:
# test-nix-env.nu (synthetic scripts) and test-nix-env-real.nu (real Nix).

# Scripts tried, in order, when no explicit script is given.
const NIX_PROFILE_CANDIDATES = [
    # Multi-user (daemon) install; the official installer hooks this one into
    # /etc/bashrc and /etc/zshrc.
    "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
    # Single-user install.
    "~/.nix-profile/etc/profile.d/nix.sh"
    # Fallback; normally unreachable, as nix-daemon.sh ships alongside it.
    "/nix/var/nix/profiles/default/etc/profile.d/nix.sh"
]

# Frames the `env -0` snapshots in bash's output; must match the printf calls
# in load-nix-env. Environment values cannot contain NUL, so the marker cannot
# occur inside a snapshot.
const ENV_SNAPSHOT_SEP = "\u{0}\u{0}SEP\u{0}\u{0}"

# Variables bash maintains itself; they are never imported or removed.
# - PWD/OLDPWD: a script that `cd`s must not move Nushell, and load-env
#   rejects PWD outright ("PWD cannot be set manually").
# - SHLVL/_: bash rewrites these per process and per command; bash >= 5.1
#   even decrements SHLVL when it runs the last command of a -c string
#   without forking.
const BASH_MANAGED_VARS = [PWD OLDPWD SHLVL _]

# Parse a null-delimited `env -0` blob into a record { KEY: VALUE, ... }.
#
# Splits each record at its *first* '=' so values containing '=' survive, and
# splits records on NUL so values containing newlines survive. Records with an
# empty key (or no '=' at all) are dropped; for duplicate keys the last wins.
export def parse-env0 []: string -> record {
    split row (char nul)
    | each { split row --number 2 "=" }
    | where { |kv| ($kv | length) == 2 and ($kv.0 | is-not-empty) }
    | reduce --fold {} { |kv, acc| $acc | upsert $kv.0 $kv.1 }
}

# Whether the current user can read `file`. Nushell has no access(2) check,
# and mode bits alone miss ownership, ACLs, and root, so just try opening it.
def is-readable [file: string]: nothing -> bool {
    try { open --raw $file | ignore; true } catch { false }
}

# Pick the profile script to source: a readable regular file, or null.
#
# With an explicit `script`, only that path is considered, so a typo surfaces
# as an error instead of silently loading a different script. Otherwise the
# first usable entry of `candidates` wins.
#
# Paths are returned expanded with --no-symlink, keeping the spelling the
# caller knows (/nix/var/nix/profiles/default/... rather than a /nix/store
# path; macOS's /var/... rather than /private/var/...). Only the type check
# resolves symlinks, because `path type` reports a symlink as "symlink".
export def resolve-nix-script [
    script?: path
    --candidates: list<string> = $NIX_PROFILE_CANDIDATES  # searched when `script` is omitted
]: nothing -> oneof<string, nothing> {
    let paths = if $script != null { [$script] } else { $candidates }

    $paths
    | path expand --no-symlink
    | where { |p| ($p | path expand | path type) == "file" and (is-readable $p) }
    | get -o 0
}

# Load a POSIX profile script's environment into Nushell.
#
# Raises, leaving the environment untouched, if an explicit `script` is not a
# readable file or if bash does not finish sourcing the script (it called
# `exit` or `exec`, or tripped `set -e` or `set -u`). With no script given and
# none found, prints a note and does nothing.
#
# Known limitations of running the script in a captured child bash:
# - TTY checks such as `[ -t 2 ]` see a pipe, so TTY-only messages are skipped.
# - A background job the script starts without redirecting its output keeps
#   the capture pipes open, delaying the load until that job exits.
export def --env load-nix-env [
    script?: path  # profile script to source (default: first usable NIX_PROFILE_CANDIDATES entry)
]: nothing -> nothing {
    let target = (resolve-nix-script $script)

    if $target == null {
        if $script != null {
            error make { msg: $"load-nix-env: not a readable file: ($script)" }
        }
        print -e "load-nix-env: no Nix profile script found; skipping."
        return
    }

    # Bash snapshots the exported environment with `env -0` (null-delimited,
    # so values may contain newlines or '='), sources the script, and
    # snapshots again. Details:
    # - The script path arrives as $1 rather than being spliced into the
    #   program, where spaces or shell metacharacters would break parsing or
    #   run as code. `set --` then clears it, so the script sees no arguments,
    #   as when a login shell sources it.
    # - `env` is located before sourcing (`type -P` skips shell functions), so
    #   a script that rewrites PATH cannot break the second snapshot.
    # - The script's output is sent to stderr, where it cannot be mistaken for
    #   snapshot data; it is forwarded below.
    # - The script's exit status is ignored: it is just the status of whatever
    #   ran last, so ordinary profiles ending in `[ -e x ] && export y` report
    #   failure while having succeeded. Bash keeps their exports, so we do too.
    # - Completion is checked instead: the closing marker is printed only after
    #   the second snapshot succeeds. Without it, the "after" snapshot is
    #   missing or truncated, and diffing against it would look like the
    #   script unset every variable.
    # - BASH_ENV is hidden from this bash. Non-interactive bash sources it
    #   first, so if it loaded Nix, the "before" snapshot would already include
    #   Nix's variables and nothing would look changed.
    let capture = (do {
        hide-env --ignore-errors BASH_ENV
        ^bash -c '
            script=$1
            set --
            nix_env_nu_env=$(type -P env) || exit
            "$nix_env_nu_env" -0 || exit
            printf "\0\0SEP\0\0"
            . "$script" >&2
            "$nix_env_nu_env" -0 && printf "\0\0SEP\0\0"
        ' bash $target
    } | complete)

    if ($capture.stderr | is-not-empty) {
        print -e -n -r $capture.stderr
    }

    # `complete` returns binary when any byte is not valid UTF-8; decode it
    # lossily rather than fail. Expect [before, after, rest]: anything after
    # the closing marker (e.g. output from an EXIT trap the script set) is
    # ignored.
    let snapshots = ($capture.stdout | into binary | decode utf-8 | split row $ENV_SNAPSHOT_SEP)
    if ($snapshots | length) < 3 {
        error make { msg: $"load-nix-env: bash did not finish sourcing ($target) \(exit code ($capture.exit_code)\); environment not imported." }
    }
    let before = ($snapshots.0 | parse-env0)
    let after = ($snapshots.1 | parse-env0)

    # Variables the script added or changed, applied with a single load-env.
    # load-env validates the whole record before setting anything, so one bad
    # key cannot leave a partial import behind.
    let updates = (
        $after
        | transpose key value
        | where { |kv| $kv.key not-in $BASH_MANAGED_VARS and ($before | get -o $kv.key) != $kv.value }
        | reduce --fold {} { |kv, acc| $acc | insert $kv.key $kv.value }
    )

    # Nushell keeps PATH as a list. It also expands `~` in PATH entries when
    # passing PATH to bash, so such entries come back expanded whenever the
    # script changes PATH. nix.sh, unlike nix-daemon.sh, has no source guard:
    # loading it again prepends duplicate entries, just as in bash.
    load-env (if "PATH" in $updates {
        $updates | update PATH { split row (char esep) }
    } else {
        $updates
    })

    # Variables the script unset. Both snapshots come from the same bash
    # process, so a key present before and absent after was genuinely unset.
    # Nix's own scripts never do this, but a custom profile script might.
    let removed = (
        $before
        | columns
        | where { |k| $k not-in $after and $k not-in $BASH_MANAGED_VARS }
    )
    hide-env --ignore-errors ...$removed
}
