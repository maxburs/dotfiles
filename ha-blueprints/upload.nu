const ROOT = path self .
const HA_URL = 'http://homeassistant.local:8123'
# 1Password API Credential item whose "credential" field holds a Home Assistant
# long-lived access token. See README.md for setup.
const TOKEN_ITEM = 'Home Assistant (ha-yellow)'

cd $ROOT

if (which op | is-empty) {
  error make {msg: "1Password CLI isn't installed. Run: brew install --cask 1password-cli"}
}
# 1Password asks you to approve the first use in each terminal session.
let token = do { ^op item get $TOKEN_ITEM --fields label=credential --reveal } | complete
if $token.exit_code != 0 {
  error make {msg: $"Couldn't read the Home Assistant token from the 1Password item '($TOKEN_ITEM)': ($token.stderr | str trim)"}
}

let files = glob --no-dir --no-symlink '{automation,script,template}/**/*.{yaml,yml}' | path relative-to $ROOT
if ($files | is-empty) {
  error make {msg: "No blueprint YAML files found to upload."}
}

with-env {COPYFILE_DISABLE: '1'} {
  ^tar -cf - ...$files | ^ssh -T ha-yellow 'mkdir -p /config/blueprints && tar -xof - -C /config/blueprints'
}

# Fails without reloading anything if the configuration is invalid.
http post --content-type application/json --headers {Authorization: $"Bearer ($token.stdout | str trim)"} $"($HA_URL)/api/services/homeassistant/reload_all" {} | ignore
print "Uploaded blueprints and reloaded all YAML configuration."
