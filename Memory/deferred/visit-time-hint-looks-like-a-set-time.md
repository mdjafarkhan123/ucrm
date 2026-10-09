# Visit time hint looks like a set time

On the New Job form, an empty visit time shows a grey "9:30 AM" hint (`TimePickerField.svelte`), which reads
like a chosen time. Saving without typing a time stores the visit as "Anytime", so the user thinks they booked
9:30 when they didn't. Found during client-reminders Part 4 proof, 2026-10-09.

**Why it waits:** outside client-reminders; nothing is broken, it only misleads.
**Brings it back:** a scheduling or form-polish pass, or a contractor reporting a visit "lost its time".
