# test-nix-env-real.nu — integration tests against the real Nix install.
#
# Checks that load-nix-env reproduces what bash itself gets from the same
# profile script. Skips cleanly when no Nix profile script is found. Run with:
#
#   nu ~/workspace/dotfiles/test-nix-env-real.nu            # the script config.nu loads
#   nu ~/workspace/dotfiles/test-nix-env-real.nu <script>   # a specific profile script

const HERE = path self .
use ($HERE | path join "nix-env.nu") *

# Source guard set by nix-daemon.sh; nix.sh has none.
const NIX_GUARD = "__ETC_PROFILE_NIX_SOURCED"

# Variables Nix's profile scripts set. They are compared even when this shell
# already has the same values, alongside whatever else the script changed.
const NIX_VARS = [PATH NIX_PROFILES NIX_SSL_CERT_FILE XDG_DATA_DIRS]

def --env check [actual, expected, name: string]: nothing -> nothing {
    if $actual == $expected {
        print $"  ok   ($name)"
        $env.TESTS_PASSED += 1
    } else {
        print $"  FAIL ($name): expected ($expected | to nuon), got ($actual | to nuon)"
        $env.TESTS_FAILED += 1
    }
}

# Bash's exported environment, after sourcing `script` if one is given.
def bash-env [script?: string]: nothing -> record {
    ^bash -c '[ -z "$1" ] || . "$1" >/dev/null 2>&1; env -0' bash ($script | default "") | parse-env0
}

def main [
    script?: path  # profile script to test (default: the one load-nix-env picks)
]: nothing -> nothing {
    let target = (resolve-nix-script $script)
    if $target == null {
        if $script != null {
            error make { msg: $"not a readable file: ($script)" }
        }
        print "No Nix profile script found; skipping real-Nix tests."
        exit 0
    }
    print $"Testing ($target)"

    $env.TESTS_PASSED = 0
    $env.TESTS_FAILED = 0

    # Start both sides from the same state. If this shell already loaded Nix
    # (the usual case, since config.nu does it at startup), nix-daemon.sh's
    # guard is in our env and would turn the script into a no-op in every
    # child bash, reducing each comparison to `$env.PATH == $env.PATH`.
    # load-nix-env ignores BASH_ENV, so the reference bash must too.
    hide-env --ignore-errors $NIX_GUARD BASH_ENV

    # Ground truth, captured before load-nix-env changes our environment.
    let baseline = (bash-env)
    let expected = (bash-env $target)
    let changed = ($expected | columns | where { |k| ($baseline | get -o $k) != ($expected | get $k) })

    load-nix-env $target

    # 1. Parity with bash for the Nix variables and anything else the script
    #    changed; null on both sides means unset in both.
    check ($changed | is-not-empty) true "sourcing changes something in bash (comparison is not vacuous)"
    for v in ($NIX_VARS | append $changed | uniq) {
        let got = if $v == "PATH" { $env.PATH | str join (char esep) } else { $env | get -o $v }
        check $got ($expected | get -o $v) $"($v) matches bash"
    }

    # 2. The result works: nix resolves, and the cert file, if set, exists.
    check (which nix | is-not-empty) true "nix resolvable on PATH"
    if $env.NIX_SSL_CERT_FILE? != null {
        check ($env.NIX_SSL_CERT_FILE | path exists) true "NIX_SSL_CERT_FILE exists"
    }

    # 3. The script added no empty PATH entries. An inherited empty entry is
    #    kept, as in bash, so compare against the baseline instead of zero.
    let count_empty = { |entries| $entries | where { |p| ($p | str trim) == "" } | length }
    let empties_before = (do $count_empty ($baseline.PATH | split row (char esep)))
    check (do $count_empty $env.PATH) $empties_before "no empty PATH entries introduced"

    # 4. Reloading is a no-op thanks to the source guard. nix.sh has no guard,
    #    so reloading it prepends duplicates (in bash too); skip it there.
    if (open --raw $target | decode utf-8 | str contains $NIX_GUARD) {
        let path_before_reload = $env.PATH
        load-nix-env $target
        check $env.PATH $path_before_reload "reloading leaves PATH unchanged"
    } else {
        print $"  skip reload check: ($target | path basename) has no source guard"
    }

    print $"\n($env.TESTS_PASSED) passed, ($env.TESTS_FAILED) failed"
    if $env.TESTS_FAILED > 0 { exit 1 }
}

