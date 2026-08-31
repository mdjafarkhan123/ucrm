// Automation has a working access decision, engine, and recipe authoring, but its contractor-facing surfaces
// (the Settings card and the Quote record-level controls) stay hidden from ordinary packages until the
// approved limited pilot opens. One flag gates every such surface so they turn on together; the per-surface
// permission and entitlement gates already decide who may see it once it is on. Part 6D flips this to true.
export const AUTOMATION_JOURNEY_READY = false;
