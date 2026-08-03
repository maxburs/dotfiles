# nix-env.nu — load Nix's POSIX profile script into Nushell.
#
# Installer support for Nix issue: https://github.com/NixOS/nix/issues/9813
#
# Runs nix.sh in bash, captures the environment it produces (null-delimited),
# diffs it against the pre-existing env, and imports only the changed vars.
# PATH is converted to a Nushell list. Source this from your config.nu, e.g.:
#
#   source ~/.config/nushell/nix-env.nu
#   load-nix-env
#
# Optionally pass a specific script path. Unlike the default search, an
# explicit path must exist — it never silently falls back to another script:
#
#   load-nix-env "/nix/var/nix/profiles/default/etc/profile.d/nix.sh"

# Default search order when no explicit script is given.
const NIX_PROFILE_CANDIDATES = [
    "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
    "~/.nix-profile/etc/profile.d/nix.sh"
    "/nix/var/nix/profiles/default/etc/profile.d/nix.sh"
]

# Parse a null-delimited `env -0` blob into a record { KEY: VALUE, ... }.
#
# Splits each record at its *first* '=' so values containing '=' survive, and
# splits records on NUL so values containing newlines survive. Records with an
# empty key (or no '=' at all) are dropped.
def parse-env0 []: string -> record {
    $in
    | split row "\u{0}"
    | where { |line| ($line | str index-of "=") > 0 }
    | reduce --fold {} { |line, acc|
        let i = ($line | str index-of "=")
        let k = ($line | str substring 0..($i - 1))
        let v = ($line | str substring ($i + 1)..)
        $acc | upsert $k $v
    }
}

# Pick the profile script to source.
#
# With an explicit `script`, returns it if it exists and null otherwise — it
# deliberately does not fall through to the defaults, so a typo surfaces as an
# error instead of silently loading a different script. With no argument,
# returns the first existing default candidate, or null if none exist.
def resolve-nix-script [script?: string]: nothing -> any {
    let candidates = if $script != null { [$script] } else { $NIX_PROFILE_CANDIDATES }

    $candidates
    | each { |c| $c | path expand --no-symlink }
    | where { |c| $c | path exists }
    | get -o 0
}

# Load a POSIX profile script's environment into Nushell.
#
# Limitation: only added and changed variables are imported; see the `hide-env`
# loop below for the (rarely exercised) removal case.
def --env load-nix-env [
    script?: string  # path to a POSIX profile script (defaults to common Nix locations)
]: nothing -> nothing {
    let target = (resolve-nix-script $script)

    if $target == null {
        if $script != null {
            error make { msg: $"load-nix-env: profile script not found: ($script)" }
        }
        print -e "load-nix-env: no Nix profile script found; skipping."
        return
    }

    # Capture before/after env as null-delimited key=value records, so values
    # containing newlines or '=' are parsed safely.
    #
    # The path is passed as an argument ($1) rather than interpolated into the
    # program text: splicing it in would let a path containing spaces or shell
    # metacharacters break parsing or execute as code.
    let dump = (bash -c 'env -0; printf "\0\0SEP\0\0"; . "$1"; env -0' bash $target)

    let halves = ($dump | split row "\u{0}\u{0}SEP\u{0}\u{0}")
    if ($halves | length) != 2 {
        error make { msg: $"load-nix-env: unexpected output from bash while sourcing ($target); environment not imported." }
    }
    let before = ($halves | get 0 | parse-env0)
    let after  = ($halves | get 1 | parse-env0)

    # Import only keys that were added or changed by the script.
    for kv in ($after | transpose key value) {
        let k = $kv.key
        let v = $kv.value
        if ($before | get -o $k) != $v {
            if $k == "PATH" {
                $env.PATH = ($v | split row (char esep))
            } else {
                load-env { $k: $v }
            }
        }
    }

    # Drop keys the script unset. Both snapshots come from the same bash
    # process, so a key present before and absent after was genuinely unset.
    # Nix's own scripts never do this, but a custom profile script might.
    let gone = ($before | columns | where { |k| $k not-in ($after | columns) })
    for k in $gone {
        hide-env --ignore-errors $k
    }
}
