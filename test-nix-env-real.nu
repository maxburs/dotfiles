# test-nix-env-real.nu — integration tests against real Nix state.
# Skips cleanly if Nix isn't installed. Run:  nu ~/workspace/dotfiles/test-nix-env-real.nu

const HERE = path self .
source ($HERE | path join "nix-env.nu")

let script = "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
if not ($script | path exists) {
    print "No Nix profile found; skipping real-state tests."
    exit 0
}

mut passed = 0
mut failed = 0
def assert [cond: bool, name: string]: nothing -> bool {
    if $cond { print $"  ok   ($name)"; true } else { print $"  FAIL ($name)"; false }
}

# Ground truth: what bash produces from the same script.
#
# nix-daemon.sh guards itself with __ETC_PROFILE_NIX_SOURCED. Once load-nix-env
# has run, that guard lives in our env and is inherited by any child bash,
# which makes the script a no-op there and turns these comparisons into
# `$env.PATH == $env.PATH`. Unset the guard so the child does real work.
def bash-var [script: string, v: string]: nothing -> string {
    bash -c 'unset __ETC_PROFILE_NIX_SOURCED; . "$1"; printf "%s" "${!2}"' bash $script $v
}

# The comparison must be symmetric. If this shell already has Nix loaded (the
# usual case — config.nu does it at startup), the guard is in our env and
# load-nix-env's child bash would no-op while bash-var's child re-runs the
# script and re-prepends its entries. Drop the guard here so both sides start
# from the same state and both do real work.
hide-env --ignore-errors __ETC_PROFILE_NIX_SOURCED

# Capture expectations BEFORE mutating our own environment, so the child bash
# starts from the same state load-nix-env will see.
let vars = [PATH NIX_PROFILES NIX_SSL_CERT_FILE XDG_DATA_DIRS]
let expected = ($vars | reduce --fold {} { |v, acc| $acc | upsert $v (bash-var $script $v) })

load-nix-env $script

# 1. PATH parity: Nu list rejoined matches bash PATH order exactly.
let got_path = ($env.PATH | str join (char esep))
if (assert ($got_path == $expected.PATH) "PATH matches bash exactly") { $passed += 1 } else { $failed += 1 }

# 2. Other key vars match bash verbatim.
for v in ($vars | where { |v| $v != "PATH" }) {
    if (assert (($env | get -o $v) == ($expected | get $v)) $"($v) matches bash") { $passed += 1 } else { $failed += 1 }
}

# 3. nix tooling actually resolves on PATH.
if (assert ((which nix | length) > 0) "nix resolvable on PATH") { $passed += 1 } else { $failed += 1 }

# 4. SSL cert file actually exists.
if (assert ($env.NIX_SSL_CERT_FILE | path exists) "cert file exists") { $passed += 1 } else { $failed += 1 }

# 5. No empty PATH entries leaked in.
if (assert (($env.PATH | where {|p| ($p | str trim) == ""} | length) == 0) "no empty PATH entries") { $passed += 1 } else { $failed += 1 }

# 6. Idempotent: reloading yields an identical PATH (no growth, no reorder).
let p1 = $env.PATH
load-nix-env $script
if (assert ($env.PATH == $p1) "idempotent PATH") { $passed += 1 } else { $failed += 1 }

# 7. The guard nix-daemon.sh sets was actually imported — this is what makes
#    repeated loads cheap, and what test 0's `unset` above compensates for.
if (assert ($env.__ETC_PROFILE_NIX_SOURCED? == "1") "nix source guard imported") { $passed += 1 } else { $failed += 1 }

print $"\n($passed) passed, ($failed) failed"
if $failed > 0 { exit 1 }

