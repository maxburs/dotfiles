# test-nix-env.nu — unit tests for nix-env.nu, using synthetic profile scripts.
# Run with:  nu ~/workspace/dotfiles/nix/test-nix-env.nu
#
# Real-Nix integration coverage lives in test-nix-env-real.nu.
#
# Tests share one environment and run in order; some rely on variables an
# earlier test imported. Cases that could damage the environment run inside a
# plain `do { }`, which discards env changes when it returns, and hand back a
# record that is checked outside it.

# Resolve relative to this file so the tests exercise the checkout they ship
# with (e.g. a git worktree) rather than whatever is in ~/workspace/dotfiles.
const HERE = path self .
const MODULE = ($HERE | path join "nix-env.nu")
use $MODULE *
use std/assert

# check (below) records a failure and moves on; assert is for preconditions
# that make the remaining tests meaningless when they fail.
assert (which bash | is-not-empty) "bash is required"

# Keep the reference bash runs below hermetic; Test 15 sets BASH_ENV itself.
hide-env --ignore-errors BASH_ENV

# The counters live in $env so `check`, a --env command, can update them.
$env.TESTS_PASSED = 0
$env.TESTS_FAILED = 0

def --env check [actual, expected, name: string]: nothing -> nothing {
    if $actual == $expected {
        print $"  ok   ($name)"
        $env.TESTS_PASSED += 1
    } else {
        print $"  FAIL ($name): expected ($expected | to nuon), got ($actual | to nuon)"
        $env.TESTS_FAILED += 1
    }
}

# Write a profile script into `dir` and return its path.
def make-script [dir: string, name: string, body: string]: nothing -> string {
    let p = ($dir | path join $name)
    $body | save -f $p
    $p
}

# PATH as child processes see it, which is what load-nix-env's bash starts
# from. It can differ from $env.PATH: Nushell expands `~` entries on export,
# such as the literal `~/.dotnet/tools` that macOS's
# /etc/paths.d/dotnet-cli-tools adds.
def exported-path []: nothing -> list<string> {
    ^bash -c 'printf "%s" "$PATH"' | split row (char esep)
}

let workdir = (mktemp -d)

try {
    # --- Test 1: synthetic script imports values, incl. tricky ones ---
    let tmp = (make-script $workdir "profile.sh" 'export FOO=bar
export PATHLIKE=/a:/b:/c
export WITH_EQ=key=val=more
export EMPTY=
export MULTILINE="one
two"
export PATH="/nix/x/bin:$PATH"
')

    let path_before = (exported-path)
    load-nix-env $tmp
    check $env.FOO? "bar" "FOO imported"
    check $env.WITH_EQ? "key=val=more" "value with '=' preserved"
    check $env.EMPTY? "" "empty value round-trips"
    check $env.MULTILINE? "one\ntwo" "value with newline preserved"
    check $env.PATHLIKE? "/a:/b:/c" "colon-separated non-PATH var stays a string"
    check ($env.PATH | describe | str starts-with "list") true "PATH is a list"
    check ($env.PATH | first) "/nix/x/bin" "PATH prepend applied"
    check ($env.PATH | slice 1..) $path_before "PATH preserves prior entries in order"

    # --- Test 2: explicit nonexistent path errors, no silent fallback ---
    # Regression: this used to fall through to the real Nix profile and quietly
    # load it, so the "missing script" branch was never exercised.
    let missing_error = (try { load-nix-env "/no/such/file.sh"; null } catch { |e| $e.msg })
    check $missing_error "load-nix-env: not a readable file: /no/such/file.sh" "explicit missing script raises"
    check $env.FOO? "bar" "missing script does not clobber env"

    # --- Test 3: resolution logic ---
    check (resolve-nix-script "/no/such/file.sh") null "resolve: missing explicit path -> null"
    # Relies on --no-symlink: on macOS, mktemp paths live under /var, a symlink
    # to /private/var.
    check (resolve-nix-script $tmp) $tmp "resolve: existing explicit path -> itself"
    check (resolve-nix-script --candidates ["/no/such.sh" $tmp]) $tmp "resolve: first usable candidate wins"
    check (resolve-nix-script --candidates ["/no/such.sh"]) null "resolve: no usable candidate -> null"

    # --- Test 4: paths with spaces and shell metacharacters are safe ---
    # Regression: the script path used to be spliced into the bash program text,
    # so these either broke sourcing or executed as code.
    let spacedir = ($workdir | path join "dir with spaces")
    mkdir $spacedir
    let spaced = (make-script $spacedir "profile.sh" "export SPACED=yes\n")
    load-nix-env $spaced
    check $env.SPACED? "yes" "path containing spaces sources correctly"

    let evil = (make-script $workdir "evil.sh; export INJECTED=yes; :" "export BENIGN=yes\n")
    load-nix-env $evil
    check $env.INJECTED? null "path metacharacters are not executed"
    check $env.BENIGN? "yes" "path metacharacters still source the real file"

    # --- Test 5: variables the script unsets are removed ---
    $env.WILL_UNSET = "here"
    load-nix-env (make-script $workdir "unset.sh" "unset WILL_UNSET\n")
    check $env.WILL_UNSET? null "unset variable is removed"

    # --- Test 6: unrelated pre-existing vars are left alone ---
    $env.UNRELATED = "untouched"
    load-nix-env (make-script $workdir "noop.sh" "export NOOP=1\n")
    check $env.UNRELATED? "untouched" "unrelated vars survive"

    # --- Test 7: a profile's trailing exit status is not a failure signal ---
    # `[ -e missing ] && export x` is an ordinary idiom that leaves $? nonzero.
    # Bash keeps the exports, so we must too.
    let trailing = (make-script $workdir "trailing.sh" 'export TOOL_HOME=/opt/tool
[ -e /definitely/not/here ] && export EXTRA=1
')
    let bash_status = (do { ^bash -c '. "$1"' bash $trailing } | complete | get exit_code)
    assert equal $bash_status 1 "trailing.sh must exit nonzero under bash for Test 7 to mean anything"
    load-nix-env $trailing
    check $env.TOOL_HOME? "/opt/tool" "nonzero trailing status still imports"

    # A script that exports and then returns nonzero: bash keeps the export.
    let failing = (make-script $workdir "failing.sh" "export PARTIAL_IMPORT=bad\nreturn 23\n")
    let bash_partial = (do { ^bash -c '. "$1"; printf "%s" "$PARTIAL_IMPORT"' bash $failing } | complete | get stdout)
    load-nix-env $failing
    check $env.PARTIAL_IMPORT? $bash_partial "early-return exports match bash"

    # --- Test 8: unusable targets are rejected up front ---
    let adir = ($workdir | path join "a-directory")
    mkdir $adir
    let dir_errored = (try { load-nix-env $adir; false } catch { true })
    check $dir_errored true "directory raises instead of silently no-op"
    check (resolve-nix-script $adir) null "resolve: directory -> null"

    # Regression: an unreadable script passed resolution, bash printed
    # "Permission denied", and the load reported success. Root can read
    # mode-000 files, so this only applies to other users.
    if (^id -u | str trim) != "0" {
        let unreadable = (make-script $workdir "unreadable.sh" "export UNREADABLE=1\n")
        ^chmod 000 $unreadable
        let unreadable_errored = (try { load-nix-env $unreadable; false } catch { true })
        check $unreadable_errored true "unreadable script raises"
        check (resolve-nix-script $unreadable) null "resolve: unreadable -> null"
    }

    # --- Test 9: profile stdout is diverted to stderr, outside the capture ---
    # Runs in a child nu, since checking what reaches stderr means capturing it
    # from outside the process.
    let noisy = (make-script $workdir "noisy.sh" "printf '\\0\\0SEP\\0\\0noise'\nexport NOISY_IMPORT=yes\n")
    let runner = (make-script $workdir "runner.nu" $'use ($MODULE | to nuon) load-nix-env
load-nix-env ($noisy | to nuon)
print $env.NOISY_IMPORT
')
    let noisy_result = (do { ^$nu.current-exe --no-config-file $runner } | complete)
    check $noisy_result.exit_code 0 "profile stdout does not break capture"
    check ($noisy_result.stdout | str trim) "yes" "profile with stdout still imports env"
    check ($noisy_result.stderr | str contains "noise") true "profile stdout is forwarded to stderr"

    # --- Test 10: a script that never finishes must not wipe the environment ---
    # Regression: when bash exited early, the "after" snapshot was simply empty,
    # so every variable looked unset and PWD, HOME, and PATH were all hidden.
    let early_exits = {
        "exit 0": "export EARLY=1\nexit 0\n"
        "exit 3": "export EARLY=1\nexit 3\n"
        "set -e failure": "set -e\nexport EARLY=1\nfalse\n"
        "set -u unbound variable": "set -u\nexport EARLY=1\n: \"$NEVER_SET_ANYWHERE\"\n"
        "exec": "export EARLY=1\nexec true\n"
    }
    for case in ($early_exits | transpose name body) {
        let script = (make-script $workdir $"early ($case.name).sh" $case.body)
        let probe = (do {
            let error = (try { load-nix-env $script; null } catch { |e| $e.msg })
            {error: $error, core: [$env.PWD? $env.HOME? $env.PATH?], early: $env.EARLY?}
        })
        check ($probe.error | default "" | str contains "did not finish sourcing") true $"($case.name): raises 'did not finish sourcing'"
        check $probe.core [$env.PWD $env.HOME $env.PATH] $"($case.name): PWD, HOME, PATH intact"
        check $probe.early null $"($case.name): nothing imported"
    }

    # --- Test 11: `env` is located before the script can change PATH ---
    # A script that replaces PATH outright still yields a complete snapshot,
    # and its PATH is imported just as bash keeps it. Isolated so the bogus
    # PATH does not reach later tests.
    let replacer = (make-script $workdir "replace-path.sh" "export PATH=/replaced/bin\nexport AFTER_REPLACE=1\n")
    let replaced = (do {
        let errored = (try { load-nix-env $replacer; false } catch { true })
        {errored: $errored, path: $env.PATH, after: $env.AFTER_REPLACE?}
    })
    check $replaced {errored: false, path: ["/replaced/bin"], after: "1"} "script that replaces PATH imports it like bash"

    # --- Test 12: variables bash manages itself are left alone ---
    # Regression: a script that `cd`s made load-env fail with "PWD cannot be
    # set manually" partway through, importing only the variables listed
    # before PWD.
    let pwd_before = $env.PWD
    let oldpwd_before = $env.OLDPWD?
    let cd_script = (make-script $workdir "cd.sh" "export CD_FIRST=1\ncd /\nexport CD_LAST=1\n")
    let cd_errored = (try { load-nix-env $cd_script; false } catch { true })
    check $cd_errored false "script that cd's does not raise"
    check [$env.CD_FIRST? $env.CD_LAST?] ["1" "1"] "script that cd's imports all its exports"
    check [$env.PWD $env.OLDPWD?] [$pwd_before $oldpwd_before] "script that cd's leaves PWD and OLDPWD alone"

    # --- Test 13: a non-UTF-8 byte does not abort the import ---
    # Regression: `complete` returned binary output, and parsing it raised.
    let weird = (make-script $workdir "weird.sh" "export WEIRD=\"$(printf '\\377')\"\nexport AFTER_WEIRD=yes\n")
    let weird_errored = (try { load-nix-env $weird; false } catch { true })
    check $weird_errored false "invalid UTF-8 does not raise"
    check $env.AFTER_WEIRD? "yes" "invalid UTF-8 still imports other vars"

    # --- Test 14: a pre-existing variable is updated in place ---
    $env.CHANGEME = "old"
    load-nix-env (make-script $workdir "change.sh" "export CHANGEME=\"$CHANGEME:new\"\n")
    check $env.CHANGEME? "old:new" "pre-existing variable is updated"

    # --- Test 15: BASH_ENV cannot pre-apply the script ---
    # Regression: non-interactive bash sources $BASH_ENV first. When that file
    # loaded the same profile, the "before" snapshot already had its variables,
    # nothing looked changed, and nothing was imported.
    let via_profile = (make-script $workdir "bash-env-profile.sh" "export VIA_PROFILE=1\n")
    let bash_env_file = (make-script $workdir "bash-env.sh" $". ($via_profile | to nuon)\n")
    let bash_env_probe = (do {
        $env.BASH_ENV = $bash_env_file
        load-nix-env $via_profile
        {imported: $env.VIA_PROFILE?, bash_env: $env.BASH_ENV?}
    })
    check $bash_env_probe.imported "1" "BASH_ENV does not hide the script's changes"
    check $bash_env_probe.bash_env $bash_env_file "Nushell's own BASH_ENV is untouched"

    # --- Test 16: the script is sourced the way a login shell sources it ---
    # It sees no positional arguments, and output from an EXIT trap it sets
    # (which runs after the closing marker) is ignored rather than parsed.
    let login_like = (make-script $workdir "login-like.sh" "trap 'echo bye' EXIT\nexport ARGC=$#\n")
    let login_errored = (try { load-nix-env $login_like; false } catch { true })
    check $login_errored false "EXIT-trap output after the final snapshot is ignored"
    check $env.ARGC? "0" "script sees no positional arguments"

    # --- Test 17: a failure before sourcing is reported as such ---
    # Regression: it used to say "did not finish sourcing". With only bash on
    # PATH, bash can't find `env` for the first snapshot. Isolated so the bare
    # PATH doesn't leak.
    let bash_only = ($workdir | path join "bash-only")
    mkdir $bash_only
    ^ln -s (which bash | get 0.path) ($bash_only | path join "bash")
    let no_env_error = (do {
        $env.PATH = [$bash_only]
        try { load-nix-env $tmp; null } catch { |e| $e.msg }
    })
    check ($no_env_error | default "" | str contains "could not snapshot") true "failure before sourcing is reported as such"
} catch { |err|
    # Unexpected error: clean up, then report it as a failure.
    rm -rf $workdir
    print -e $err.rendered
    exit 2
}

rm -rf $workdir
print $"\n($env.TESTS_PASSED) passed, ($env.TESTS_FAILED) failed"
if $env.TESTS_FAILED > 0 { exit 1 }

