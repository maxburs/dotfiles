const ROOT = path self .
const HA_URL = 'http://homeassistant.local:8123'
# A long-lived access token (HA profile → Security), stored once in the macOS Keychain with:
#   security add-generic-password -s ha-yellow -a home-assistant -w
const TOKEN_SERVICE = 'ha-yellow'

cd $ROOT

let token = do { ^security find-generic-password -s $TOKEN_SERVICE -w } | complete
if $token.exit_code != 0 {
  error make {msg: $"No Home Assistant token in the Keychain. Create a long-lived access token in your HA profile under Security, then run: security add-generic-password -s ($TOKEN_SERVICE) -a home-assistant -w"}
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
