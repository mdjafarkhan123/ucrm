# Selectable design experiences — architecture audit

Read-only audit on 2026-10-11. No application, database, infrastructure or design-skill changes were made.
This establishes a proposed approach, not verified asset isolation or performance.

## Verified project facts

- Root `src/routes/+layout.svelte` statically imports `src/lib/styles/app.scss`, which imports
  `_variables.scss`. That token file emits `:root` definitions and dark overrides. Root styles also
  contain visual anchor, focus, scrollbar and animation rules, not just a neutral reset.
- Root layout imports the toast presentation. It can pull visual CSS into every route regardless of
  organization choice. Audit root errors, dialogs/portals and support surfaces too, not just the sidebar.
- Business layout statically imports AppShell, PageContainer, skeletons, notices and support UI.
  AppShell statically imports Sidebar, Topbar, MobileNav and several dialogs. An `{#if}` around those
  imports would not establish separate download graphs.
- AppShell owns navigation and sign-out coordination together with layout. Topbar owns local light/dark
  preference and presentation. These need shared behaviour extraction before layout adapters diverge.
- PageContainer supplies white surface, padding and radius. Record pages import this and other visual
  components directly. Job detail at `src/routes/(app)/jobs/[id=uuid]/+page.svelte` also owns queries,
  drafts and saves: copying this entire page would duplicate behaviour.
- Existing shell publishes `--shell-content-left`, `--shell-content-right`, `--shell-edge` for fixed save
  bars. New gutters must update those coordinates and retain reserved bottom space.
- Organization settings are already read by the server business layout. A future selection can be included
  in that read; no separate browser settings request is needed before the shell.
- Daily page code is warmed by `warm-pages.ts`. Theme isolation must survive both hover and idle warming;
  route wrappers must not statically import both presentation trees.
- Vite is configured through `vite.config.ts`; no CSS splitting override was found. No standalone Svelte
  configuration or the documented `additionalData` injection was found in tracked configuration inspected.
  Recheck actual SCSS preprocessing before relying on that instruction during implementation.
- Project policy requires SSR shell and CSR page content. No explicit `ssr = false` declarations were found
  in routes. Preserve the policy and verify actual rendered output during the proof; do not disable SSR on
  the whole Business Workspace merely to simplify dynamic presentation loading.

## Classic guidance recovery

Pre-Botanical design skill tree: `75d6d48432a4e846941e6b9c88d3ffd7db1f6026`
(parent of `c5ad7b08`, the Botanical alignment change). Compare that tree with current guidance before
restoring. Changes since that point affect the entry point, new alignment register and Botanical sections
in layout/sidebar modules; most historical modules remain available unchanged.

Historical frontmatter says the root uses 62.5%/10px rem units; actual `app.scss` uses 100%.
Recovery must preserve actual Classic appearance and mark stale guidance corrected rather than changing
live tokens to satisfy an obsolete document. Capture signed-in Classic screenshots before refactoring.

## Primary evidence and what it supports

- [Moodle theme architecture](https://moodledev.io/docs/5.0/apis/plugintypes/theme): themes can supply layouts,
  templates and styles over shared application behaviour. Supports separate presentation adapters, not a
  claim about our framework or Moodle downloading no inactive assets.
- [Vite CSS splitting](https://vite.dev/config/build-options.html#build-csscodesplit): CSS in asynchronous
  chunks can be fetched with those chunks. Supports explicit lazy presentation imports; does not guarantee
  SvelteKit SSR/preloads will avoid inactive assets without a built-output and browser check.
- [SvelteKit load](https://svelte.dev/docs/kit/load): server layout data can precede rendering; universal loads
  can return component constructors. Candidate: server-resolved design identifier and universal loading of
  exactly one shell adapter. Need production proof of emitted CSS links and hydration before committing to it.
- [SvelteKit page options](https://svelte.dev/docs/kit/page-options): disabling SSR produces a client-rendered
  shell, so it is not the selected workaround for the existing SSR-shell requirement.

## Proposed technical shape

A small typed registry resolves `classic | botanical` to explicit dynamic imports. Use per-surface loaders
(shell, job detail, etc.), not an eager barrel of every adapter. Share business APIs, query keys, controllers,
access decisions and mutation commands. Presentation adapters receive state/actions through typed props or
context; they may arrange genuinely different markup. Share presentation only when its styling and structure
are truly identical. Component CSS stays local; design token/font entries are the deliberate exception.

Root imports only neutral reset and required shared infrastructure. Design tokens, global visual defaults,
fonts and visual roots move behind selected entries. A CSS variable alias is not enough if it still causes
Classic-only styles to download. Never mechanically copy all components; move the selected slice first.

Resolve organization selection on the server using the existing settings read. Keep design identity separate
from `data-theme` light/dark identity. Scope both around the selected workspace, including portaled controls;
account for shared-route navigation from login, Control Room or a different workspace. Auth/public documents
retain their own declared presentation until separately planned. Unrelated-route assets already downloaded
are not proof of a workspace isolation failure; measure direct cold loads and subsequent workspace warming
separately.

Changing the active design should use a guarded full reload after saving, rather than accumulating two
presentation trees/styles in one SPA session. Confirm drafts are saved/discarded first. A new organization
context must also re-resolve selection, never reuse another organization's server state. No process-global
mutable selected-design variable. No additional custom cache; TanStack Query remains the server-state cache.

## Proof and performance design verdict

Proceed to a bounded production-build proof before a whole-app migration. Variables are available design
count, visited/warmed surfaces and fetched visual assets. Begin with two designs and one representative
shell/surface; inactive-design requests must remain zero irrespective of adding an unused registry entry.
Shared runtime and the selected presentation necessarily still download.

Before refactoring, record a production baseline: build revision, device, network/CPU settings, direct and
post-login load, compressed CSS/JS/font transfer, request graph, LCP/CLS, navigation response and shell
first-frame screenshots. Desktop 1440 is the primary visual target; 390 is the secondary safeguard.
Repeat identical scenarios after the slice. No numerical baseline or speed claim is established by this audit.
Investigate any repeatable transfer/timing regression before expanding; record approved budgets from the
measured baseline rather than inventing byte counts now. Use manifest traversal plus real browser requests,
including idle/hover preloads. Verify selected shell SSR, no wrong-design frame and no hydration mismatch.

If SvelteKit combines inactive presentation CSS into initial links, the proof fails: inspect the import graph
and revise the loading approach before migrating pages. Do not hide the issue with CSS selectors, disabling
SSR, duplicating routes or globally disabling useful preloading. Record the proven mechanism in an ADR.

## Remaining decisions and evidence gaps

Jafar confirmed organization-wide owner selection, personal light/dark preferences and a private Botanical
preview until complete. Classic stays live; no production Classic fallback pages within Botanical.
Business Workspace-only first release was proposed and awaits his answer. Control Room/customer-facing adoption and Botanical dark
palette are separate design work. No database migration, traffic capacity or production timing is verified.
