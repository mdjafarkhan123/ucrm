/**
 * The widget's live-transport surface, isolated in its own module so the Realtime client behind it
 * can be code-split away from the widget's first byte -- exactly as `phone.ts` isolates the
 * phone-number metadata. Nothing here loads until a visitor with an accepted session opens the panel.
 *
 * `@supabase/realtime-js` directly, not `@supabase/supabase-js`: the visitor needs one websocket and
 * one channel, and the full client would drag auth, PostgREST, Storage and Functions into a bundle
 * that runs on every page view of a stranger's website. The package documents this standalone import
 * for exactly this case. It is the same version supabase-js already resolves to.
 *
 * Re-exporting only the constructor keeps tree-shaking alive, for the same reason `phone.ts`
 * re-exports four functions instead of a namespace.
 */

export { RealtimeClient } from '@supabase/realtime-js';
