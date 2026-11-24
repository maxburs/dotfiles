# Room buttons and lights-off hours

Adaptive Lighting sets each light's brightness and color. Two blueprints build
on it:

- **BILRESA room lighting**
  ([blueprint](./automation/local/bilresa_room_lighting.yaml)): tap button 1
  to turn a room on and button 2 to turn it off. Hold button 1 for full white,
  and hold again to resume adaptive lighting.
- **Lights off policy**
  ([blueprint](./automation/local/lights_off_policy.yaml)): a list of lights,
  each with the time it turns off and the time it's allowed back on. It works
  for any light, whether or not it uses Adaptive Lighting.

## Set up

1. Set up the uploader. It reads a Home Assistant token from 1Password:
   1. Install the 1Password CLI with `brew install --cask 1password-cli`
      (listed in [brewfile.rb](../brewfile.rb)). In the 1Password app, turn on
      **Settings → Developer → Integrate with 1Password CLI**.
   2. Create a long-lived access token: open your Home Assistant profile's
      [**Security** tab](https://my.home-assistant.io/redirect/profile_security),
      scroll to **Long-lived access tokens** near the bottom, and select
      **Create token**. Home Assistant shows the token only once.
   3. In 1Password, save it as an **API Credential** item named
      `Home Assistant (ha-yellow)`, with the token in the **credential** field.

   Then, from the repo root, run `nu ha-blueprints/upload.nu`. The uploader
   copies the blueprint files to `/config/blueprints/` over SSH, using the
   `ha-yellow` alias from [ssh-config](../ssh-config), then reloads all YAML
   configuration. It doesn't delete other blueprints. If the configuration is
   invalid, Home Assistant reports the error and reloads nothing.

   1Password asks you to approve the first upload in each terminal window,
   with Touch ID or your password. It asks again after 10 minutes without a
   1Password command in that window, or after 12 hours.
2. In **Settings → Automations & scenes → Blueprints**, create an automation
   from **Lights off policy**. Add a row for each light, then save:

   | Light | Off from | Off until |
   |---|---|---|
   | Shelf light | 18:00 | 07:00 |

3. In each room's BILRESA automation, select that automation under
   **Lights off policy**.

The hold finds a room's Adaptive Lighting profiles through their devices, so
assign each profile's device to the room of its lights, and keep each profile
within one room. In a room without a profile, the hold does nothing.

To change the lights or hours later, edit the list and save.

If you set up an earlier version, remove it: the per-light `template:` entry in
`configuration.yaml`, or the labels, Schedule helpers and turn-on script. You
can also delete its old files under `/config/blueprints/template/` or
`/config/blueprints/script/`.

## Behavior

- **When a range starts**, the light turns off if it's on, unless Adaptive
  Lighting marks it as manually controlled, for example after the full-white
  hold.
- **During the range**, BILRESA's room-on tap skips the light, along with any
  Home Assistant light group in the room that contains it. Room-off and the
  full-white hold still target the whole room, so the hold turns the light on.
  If the light is in an Adaptive Lighting profile, it then stays on until you
  turn it off; otherwise it also turns off at its next range start. Turning
  Adaptive Lighting off doesn't exempt a light.
- **When the range ends**, nothing turns on.

Ranges apply every day, can cross midnight, and are checked to the minute. Equal
**Off from** and **Off until** times mean all day. A light can have more than
one row. Editing the list doesn't turn anything off until the next range starts.

Dashboard, voice, scenes and other direct commands bypass the policy. Hue rooms
and zones aren't checked for members, so if one is in the room, room-on turns it
on, including any member in its off hours. Turning the Lights off policy
automation off pauses it: ranges don't start, and buttons turn lights on
normally.

## Turn lights on from another automation

A future button can turn on a light or room through the policy. Pass exactly one
of `light` (an entity ID) or `room` (an area ID such as `living_room`, not its
display name). Anything else stops with an error and turns nothing on:

```yaml
- action: automation.trigger
  target:
    entity_id: automation.lights_off_policy  # use your automation's entity ID
  data:
    variables:
      light: light.shelf
```

## Development

From the repo root:

```sh
nix develop ./ha-blueprints --command uv run --script ha-blueprints/test_lighting.py
```

The [flake](./flake.nix) provides `uv` and Python 3.14, pinned in
`flake.lock`, and stops `uv` from downloading another Python. Nix reads the
flake from Git, so commit or `git add` changes to `flake.nix` and `flake.lock`
first. To update the pins, run `nix flake update --flake ./ha-blueprints`.

The test script declares its Home Assistant version inline. Tests load the
blueprints in a temporary HA configuration, advance a simulated clock, change
Adaptive Lighting and button states, and check which commands reach the lights
and Adaptive Lighting. No SSH, HACS, credentials or hardware are used. To test
another Core version, change the dependency pin.
