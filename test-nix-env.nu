# test-nix-env.nu — unit tests for nix-env.nu
# Run with:  nu ~/workspace/dotfiles/test-nix-env.nu
#
# Real-Nix integration coverage lives in test-nix-env-real.nu.

# Resolve relative to this file so the tests exercise the checkout they ship
# with (e.g. a git worktree) rather than whatever is in ~/workspace/dotfiles.
const HERE = path self .
source ($HERE | path join "nix-env.nu")

mut passed = 0
mut failed = 0

def assert-eq [actual, expected, name: string]: nothing -> bool {
    if $actual == $expected {
        print $"  ok   ($name)"
        true
    } else {
        print $"  FAIL ($name): expected (($expected) | to nuon), got (($actual) | to nuon)"
        false
    }
}

# Write a profile script into `dir` and return its path.
def make-script [dir: string, name: string, body: string]: nothing -> string {
    let p = ($dir | path join $name)
    $body | save -f $p
    $p
}

let workdir = (mktemp -d)

# --- Test 1: synthetic script imports values, incl. tricky ones ---
let tmp = (make-script $workdir "profile.sh" 'export FOO=bar
export PATHLIKE=/a:/b:/c
export WITH_EQ=key=val=more
export EMPTY=
export MULTILINE="one
two"
export PATH="/nix/x/bin:$PATH"
')

let path_before = $env.PATH
load-nix-env $tmp
if (assert-eq $env.FOO? "bar" "FOO imported") { $passed += 1 } else { $failed += 1 }
if (assert-eq $env.WITH_EQ? "key=val=more" "value with '=' preserved") { $passed += 1 } else { $failed += 1 }
if (assert-eq $env.EMPTY? "" "empty value round-trips") { $passed += 1 } else { $failed += 1 }
if (assert-eq $env.MULTILINE? "one\ntwo" "value with newline preserved") { $passed += 1 } else { $failed += 1 }
if (assert-eq $env.PATHLIKE? "/a:/b:/c" "colon-separated non-PATH var stays a string") { $passed += 1 } else { $failed += 1 }
if (assert-eq ($env.PATH | describe | str starts-with "list") true "PATH is a list") { $passed += 1 } else { $failed += 1 }
if (assert-eq ($env.PATH | first) "/nix/x/bin" "PATH prepend applied") { $passed += 1 } else { $failed += 1 }
if (assert-eq ($env.PATH | slice 1..) $path_before "PATH preserves prior entries in order") { $passed += 1 } else { $failed += 1 }

# --- Test 2: explicit nonexistent path errors, no silent fallback ---
# Regression: this used to fall through to the real Nix profile and quietly
# load it, so the "missing script" branch was never exercised.
let missing_errored = (try { load-nix-env "/no/such/file.sh"; false } catch { true })
if (assert-eq $missing_errored true "explicit missing script raises") { $passed += 1 } else { $failed += 1 }
if (assert-eq $env.FOO? "bar" "missing script does not clobber env") { $passed += 1 } else { $failed += 1 }

# --- Test 3: resolution logic ---
if (assert-eq (resolve-nix-script "/no/such/file.sh") null "resolve: missing explicit path -> null") { $passed += 1 } else { $failed += 1 }
if (assert-eq (resolve-nix-script $tmp) $tmp "resolve: existing explicit path -> itself") { $passed += 1 } else { $failed += 1 }

# --- Test 4: paths with spaces and shell metacharacters are safe ---
# Regression: the script path used to be spliced into the bash program text,
# so these either broke sourcing or executed as code.
let spacedir = ($workdir | path join "dir with spaces")
mkdir $spacedir
let spaced = (make-script $spacedir "profile.sh" "export SPACED=yes\n")
load-nix-env $spaced
if (assert-eq $env.SPACED? "yes" "path containing spaces sources correctly") { $passed += 1 } else { $failed += 1 }

let evil = (make-script $workdir "evil.sh; export INJECTED=yes; :" "export BENIGN=yes\n")
load-nix-env $evil
if (assert-eq $env.INJECTED? null "path metacharacters are not executed") { $passed += 1 } else { $failed += 1 }
if (assert-eq $env.BENIGN? "yes" "path metacharacters still source the real file") { $passed += 1 } else { $failed += 1 }

# --- Test 5: variables the script unsets are removed ---
$env.WILL_UNSET = "here"
let unsetter = (make-script $workdir "unset.sh" "unset WILL_UNSET\n")
load-nix-env $unsetter
if (assert-eq $env.WILL_UNSET? null "unset variable is removed") { $passed += 1 } else { $failed += 1 }

# --- Test 6: unrelated pre-existing vars are left alone ---
$env.UNRELATED = "untouched"
load-nix-env (make-script $workdir "noop.sh" "export NOOP=1\n")
if (assert-eq $env.UNRELATED? "untouched" "unrelated vars survive") { $passed += 1 } else { $failed += 1 }

rm -rf $workdir
print $"\n($passed) passed, ($failed) failed"
if $failed > 0 { exit 1 }

