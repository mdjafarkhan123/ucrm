# Missing business setup does not yet block the action that needs it

- **Priority:** P3


- **Campaign:** `contractor-settings` Part 1, scoped out 2026-08-22.
- **Reason:** the blueprint says incomplete setup blocks only the action requiring it, such as money or
  scheduling work. That enforcement belongs to each owning feature, not to Settings.
- **Reactivation trigger:** a feature needs confirmed currency, timezone, or hours to act honestly.
- **Prerequisites:** Part 1 readiness reporting shipped, so the block can link to the exact missing setting.
- **Checkpoint:** `GET /api/settings` readiness in the Part 1 packet.

