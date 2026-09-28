# Every unnamed address is called "Primary property"

**Why it waits:** `properties.label` defaults to "Primary property" and client create fills it the same way,
so a second address added without a name, or one moved over by a client merge, shows "Primary property" under
the street although it is not the main one (only the "Main" badge is right). Found 2026-09-28 in Part 10's
browser check; not caused by the merge.
**Brings it back:** any client/property UI work, or Jafar noticing it. Jobber names addresses by the street, so
the likely fix is no default label and showing the street alone.
