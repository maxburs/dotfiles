# Room buttons and lights-off hours

Adaptive Lighting sets each light's brightness and color. Two blueprints build
on it:

- **BILRESA room lighting**
  ([blueprint](./automation/local/bilresa_room_lighting.yaml)): tap button 1
  to turn a room on and button 2 to turn it off. Hold button 1 for full white,
  and hold again to resume adaptive lighting.
- **Lights off policy**
  ([blueprint](./automation/local/lights_off_policy.yaml)): a list of lights,
  each with the time it turns off and the time it's allowed back on.

## Set up

1. From the repo root, run `nu ha-blueprints/upload.nu`. The uploader copies
   the blueprint files to `/config/blueprints/` over SSH, using the
   `ha-yellow` alias from [ssh-config](../ssh-config). It doesn't delete other
   blueprints. When updating, reload automations afterward.
2. In **Settings → Automations & scenes → Blueprints**, create an automation
   from **Lights off policy**. Add a row for each light, then save:

   | Light | Off from | Off until |
   |---|---|---|
   | Shelf light | 18:00 | 07:00 |

3. In each room's BILRESA automation, select that automation under
   **Lights off policy**.

Adaptive Lighting profiles are found through each light's area. A listed light
doesn't need to be in a profile. If its area has more than one profile, enable
`include_config_in_attributes` on them; otherwise turning off just the light's
own profile won't exempt it. Enable it too under
`take_over_control_mode: pause_changed`, so a color-only override doesn't
exempt a light.

To change the lights or hours later, edit the list and save.

If you set up an earlier version, remove it: the per-light `template:` entry in
`configuration.yaml`, or the labels, Schedule helpers and turn-on script. You
can also delete its old files under `/config/blueprints/template/` or
`/config/blueprints/script/`.

## Behavior

- **When a range starts**, the light turns off if it's on, unless it's exempt.
  A light is exempt while Adaptive Lighting has it under manual control, for
  example after BILRESA's full-white hold, or while every profile in its area
  that could manage it is off or has Adapt Brightness off.
- **During the range**, BILRESA's room-on tap skips the light unless it's
  exempt, along with any Home Assistant light group in the room that contains
  it. Room-off and the full-white hold still target the whole room. Holding
  again to resume adaptation leaves a lit light on.
- **When the range ends**, nothing turns on.

Ranges apply every day, can cross midnight, and are checked to the minute. Equal
**Off from** and **Off until** times mean all day. A light can have more than
one row. Editing the list doesn't turn anything off until the next range starts.

Dashboard, voice, scenes and other direct commands bypass the policy. Bridge
groups such as Hue zones don't expose their member lights, so if one is in the
room, room-on turns it on, including any member in its off hours. Turning the
Lights off policy automation off pauses it: ranges don't start, and buttons
turn lights on normally.

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
profile and button states, and check which commands reach the lights. No SSH,
HACS, credentials or hardware are used. To test another Core version, change
the dependency pin.
