const ROOT = path self .
cd $ROOT

let files = glob --no-dir --no-symlink '{automation,script,template}/**/*.{yaml,yml}' | path relative-to $ROOT
if ($files | is-empty) {
  error make {msg: "No blueprint YAML files found to upload."}
}

with-env {COPYFILE_DISABLE: '1'} {
  ^tar -cf - ...$files | ^ssh -T ha-yellow 'mkdir -p /config/blueprints && tar -xof - -C /config/blueprints'
}
