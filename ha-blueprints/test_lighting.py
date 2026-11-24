# /// script
# requires-python = ">=3.14.2,<3.15"
# dependencies = ["homeassistant==2026.11.3"]
# ///
"""Run from the repo root: `nix develop ./ha-blueprints --command uv run --script ha-blueprints/test_lighting.py`."""

from datetime import timedelta
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import AsyncMock, patch

from homeassistant import bootstrap, config_entries, loader, setup
import probatio
from homeassistant.const import EntityCategory
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers import area_registry, config_validation as cv, device_registry, entity_registry, event
from homeassistant.helpers.entity import entity_sources
import homeassistant.util.dt as dt_util


ROOT = Path(__file__).resolve().parent
ROOM = "living_room"
SHELF, CEILING, INDICATOR, GROUP = "light.shelf", "light.ceiling", "light.indicator", "light.room_group"
ORB = "light.bedroom_orb"
POLICY = "automation.lights_off"
PROFILE, DIMMER = "switch.room_profile", "switch.room_adapt_brightness"
# HA appends a number when several remotes share a name, as with a second BILRESA.
REMOTE_BUTTON = "event.bilresa_dual_button_button_{}_3"
RANGES = [
    {"light": SHELF, "from": "18:00:00", "until": "07:00:00"},
    {"light": CEILING, "from": "18:01:00", "until": "18:02:00"},  # starts the very next minute
    {"light": ORB, "from": "18:00:00", "until": "07:00:00"},
]


class LightsOffPolicyTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        shutil.copytree(ROOT / "automation", Path(tmp.name, "blueprints", "automation"))
        h = self.hass = HomeAssistant(tmp.name)
        h.config.skip_pip = True
        loader.async_setup(h)
        h.config_entries = config_entries.ConfigEntries(h, {})
        self.assertTrue(await bootstrap.async_load_base_functionality(h))
        self.addAsyncCleanup(h.async_stop, force=True)

        # Use tomorrow so every simulated time is still ahead of HA's real timers.
        self.day = dt_util.start_of_local_day() + timedelta(days=1)
        self.clock = self.day.replace(hour=12)
        clock = patch.object(dt_util, "now", side_effect=lambda time_zone=None: self.clock)
        clock.start()
        self.addCleanup(clock.stop)

        for area in ("Living Room", "Bedroom"):
            area_registry.async_get(h).async_create(area)
        self.add_entity(SHELF)
        self.add_entity(ORB, area="bedroom")
        self.add_entity(CEILING)
        self.add_entity(INDICATOR, category=EntityCategory.CONFIG)
        await self.add_profile(PROFILE, DIMMER)
        remote = await self.add_device("matter", "BILRESA")
        for button in (1, 2):
            self.add_entity(REMOTE_BUTTON.format(button), device=remote, area=None)
            h.states.async_set(REMOTE_BUTTON.format(button), "2026-01-01T00:00:00+00:00")

        self.calls, self.light_data, self.al_calls = [], [], []

        @callback
        def light_action(call):
            self.calls.append((call.service, call.data["entity_id"] if "entity_id" in call.data else call.data["area_id"]))
            self.light_data.append({k: v for k, v in call.data.items() if k not in ("entity_id", "area_id")})
            for lamp in call.data.get("entity_id", []):
                h.states.async_set(lamp, "on" if call.service == "turn_on" else "off")

        @callback
        def al_action(call):
            self.al_calls.append((f"{call.domain}.{call.service}", dict(call.data)))

        for action in ("turn_on", "turn_off"):
            h.services.async_register("light", action, light_action,
                                      cv.make_entity_service_schema({}, extra=probatio.ALLOW_EXTRA))
        for domain, action in (("adaptive_lighting", "set_manual_control"),
                               ("adaptive_lighting", "apply"), ("switch", "turn_on")):
            h.services.async_register(domain, action, al_action)

        config = {"automation": [
            {"id": "lights_off", "alias": "Lights off", "use_blueprint": {
                "path": "local/lights_off_policy.yaml", "input": {"ranges": RANGES}}},
            {"id": "room_button", "alias": "Room button", "use_blueprint": {
                "path": "local/bilresa_room_lighting.yaml",
                "input": {"remote": remote.id, "room": ROOM, "room_on_policy": POLICY}}},
        ]}
        for domain in ("homeassistant", "automation"):
            self.assertTrue(await setup.async_setup_component(h, domain, config))
        await h.async_start()
        await h.async_block_till_done()
        for automation in (POLICY, "automation.room_button"):
            self.assertEqual(h.states.get(automation).state, "on", f"{automation} failed to load")

    def add_entity(self, entity_id, *, category=None, device=None, area=ROOM):
        domain, object_id = entity_id.split(".")
        reg = entity_registry.async_get(self.hass)
        entry = reg.async_get_or_create(
            domain, "fixture", object_id, suggested_object_id=object_id,
            device_id=device.id if device else None, entity_category=category,
        )
        reg.async_update_entity(entry.entity_id, area_id=area)
        self.assertEqual(entry.entity_id, entity_id)
        if domain == "light":
            self.hass.states.async_set(entity_id, "on")

    async def add_device(self, domain, name, area=None):
        entry = config_entries.ConfigEntry(
            domain=domain, title=name, data={}, options={}, source="user", version=1,
            minor_version=1, unique_id=None, discovery_keys={}, subentries_data=(),
        )
        with patch.object(config_entries.ConfigEntries, "async_setup", new_callable=AsyncMock):
            await self.hass.config_entries.async_add(entry)
        devices = device_registry.async_get(self.hass)
        device = devices.async_get_or_create(config_entry_id=entry.entry_id, identifiers={(domain, name)}, name=name)
        return devices.async_update_device(device.id, area_id=area)

    async def add_profile(self, profile, dimmer, **attrs):
        """Simulate an Adaptive Lighting profile device assigned to the room."""
        device = await self.add_device("adaptive_lighting", profile, area=ROOM)
        for entity_id in (profile, dimmer):
            self.add_entity(entity_id, device=device, area=None)
            entity_sources(self.hass)[entity_id] = {"domain": "adaptive_lighting"}
        self.set_profile(profile, dimmer, **attrs)

    def set_profile(self, profile=PROFILE, dimmer=DIMMER, *, state="on", dimmer_state="on",
                    manual=(), brightness=None, mode=None, lights=None):
        config = {"take_over_control_mode": mode} if mode else {}
        if lights is not None:
            config["lights"] = lights
        attrs = {"configuration": config}
        if state == "on":
            attrs |= {"manual_control": list(manual),
                      "manual_control_brightness": list(manual if brightness is None else brightness)}
        self.hass.states.async_set(profile, state, attrs)
        self.hass.states.async_set(dimmer, dimmer_state, {"icon": "mdi:brightness-4"})

    async def at(self, hhmm, day=0):
        """Advance the clock and run HA's due time listeners, like its test helper does."""
        hour, minute = map(int, hhmm.split(":"))
        # HA offsets minute timers by a random fraction of a second.
        self.clock = (self.day + timedelta(days=day)).replace(hour=hour, minute=minute, second=1)
        utc = dt_util.as_utc(self.clock)
        with (patch.object(event, "time_tracker_utcnow", return_value=utc),
              patch.object(event, "time_tracker_timestamp", return_value=utc.timestamp())):
            for handle in list(self.hass.loop._scheduled):
                if isinstance(tracker := handle._callback, event._TrackPointUTCTime) and not handle.cancelled():
                    handle.cancel()
                    tracker()
        await self.hass.async_block_till_done()

    def lights(self, service):
        return [light for called, lights in self.calls if called == service for light in lights]

    async def request(self, **variables):
        await self.hass.services.async_call(
            "automation", "trigger", {"entity_id": POLICY, "variables": variables}, blocking=True)
        await self.hass.async_block_till_done()

    async def press(self, button, event_type="multi_press_1"):
        self.hass.states.async_set(REMOTE_BUTTON.format(button), dt_util.utcnow().isoformat(),
                                   {"event_type": event_type})
        await self.hass.async_block_till_done()

    async def hold(self):
        await self.press(1, "long_press")

    async def test_range_start_turns_off_listed_lights(self):
        await self.at("17:59")
        self.assertEqual(self.calls, [])
        await self.at("18:00")
        await self.at("18:01")
        self.assertEqual(self.calls, [("turn_off", [SHELF, ORB]), ("turn_off", [CEILING])])
        await self.at("07:00", day=1)
        self.assertEqual(len(self.calls), 2)  # ending never wakes a bulb

    async def test_requests_skip_lights_in_range_like_a_normal_room_on(self):
        self.add_entity(GROUP)
        self.hass.states.async_set(GROUP, "on", {"entity_id": [SHELF, CEILING]})
        entity_sources(self.hass)[GROUP] = {"domain": "group"}
        await self.at("19:00")
        await self.request(light=SHELF)
        await self.request(light=ORB)
        await self.request(room=ROOM)
        # The configuration light and the group holding the shelf stay off.
        self.assertEqual(self.calls, [("turn_on", [CEILING])])
        await self.at("02:00", day=1)
        await self.request(light=SHELF)
        self.assertEqual(len(self.calls), 1)  # the range crosses midnight
        await self.at("07:00", day=1)
        await self.request(room=ROOM)
        self.assertEqual(self.calls[-1], ("turn_on", [ROOM]))

    async def test_policy_spares_manually_controlled_lights_only(self):
        self.set_profile(lights=[SHELF], manual=[SHELF])  # e.g. after a full-white hold
        await self.at("18:00")
        self.assertNotIn(SHELF, self.lights("turn_off"))
        self.assertIn(ORB, self.lights("turn_off"))
        self.set_profile(state="off", lights=[SHELF])  # turning Adaptive Lighting off doesn't exempt it
        await self.request(light=SHELF)
        self.assertNotIn(SHELF, self.lights("turn_on"))

    async def test_room_button_uses_policy_for_on_only(self):
        await self.at("19:00")
        for button in (1, 2):
            await self.press(button)
        self.assertEqual(self.calls, [("turn_on", [CEILING]), ("turn_off", [ROOM])])
        await self.hass.services.async_call("automation", "turn_off", {"entity_id": POLICY}, blocking=True)
        await self.press(1)
        self.assertEqual(self.calls[-1], ("turn_on", [ROOM]))  # falls back to the whole room
        await self.request(light=SHELF)
        self.assertEqual(self.calls[-1], ("turn_on", [SHELF]))  # other callers are paused too

    async def test_hold_sets_the_room_to_full_white(self):
        await self.hold()
        self.assertEqual(self.al_calls, [("adaptive_lighting.set_manual_control",
                                          {"entity_id": [PROFILE], "manual_control": True})])
        self.assertEqual(self.calls, [("turn_on", [ROOM])])
        self.assertEqual(self.light_data, [{"brightness_pct": 100, "color_temp_kelvin": 4000}])

    async def test_hold_resumes_overridden_or_disabled_adaptation(self):
        apply = ("adaptive_lighting.apply", {"entity_id": [PROFILE], "adapt_brightness": True,
                                             "adapt_color": False, "turn_on_lights": False})
        self.set_profile(manual=[CEILING])
        await self.hold()
        self.assertEqual(self.al_calls, [("adaptive_lighting.set_manual_control",
                                          {"entity_id": PROFILE, "lights": [CEILING], "manual_control": False}),
                                         apply])
        self.al_calls.clear()
        self.set_profile(dimmer_state="off")
        await self.hold()
        self.assertEqual(self.al_calls, [("switch.turn_on", {"entity_id": [DIMMER]}), apply])
        self.assertEqual(self.calls, [])

    async def test_hold_does_nothing_in_a_room_without_a_profile(self):
        devices = device_registry.async_get(self.hass)
        profile_device = entity_registry.async_get(self.hass).async_get(PROFILE).device_id
        devices.async_update_device(profile_device, area_id="bedroom")
        with self.assertLogs("homeassistant.components.automation.room_button", "INFO") as logs:
            await self.hold()
        self.assertEqual((self.calls, self.al_calls), ([], []))
        self.assertIn("Stop script sequence: No Adaptive Lighting profile in this room", "\n".join(logs.output))

    async def test_invalid_request_turns_nothing_on(self):
        await self.request(light=SHELF, room=ROOM)
        await self.request()
        self.assertEqual(self.calls, [])


if __name__ == "__main__":
    unittest.main()
