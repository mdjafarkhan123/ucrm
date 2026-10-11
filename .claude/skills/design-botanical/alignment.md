# Botanical alignment register

Read with [SKILL.md](SKILL.md) and the [shared workflow](../design/SKILL.md). Jafar approved incremental maintenance on 2026-10-11.
Keep Classic modules separate; align Botanical modules after the relevant focused demo is built and approved.
The [starter guidance](../../../docs/design/botanical-v3/README.md) owns extracted values and boundaries;
this register tracks coverage, not a second token specification.

## Redesign reading rule — approved 2026-10-11

For every redesign session, including standalone demos, load Botanical `SKILL.md`, shared `design/SKILL.md`, this register, the Botanical
starter guidance and the campaign contract. Load an additional design module only when the table below
explicitly marks its relevant coverage updated. A changed file or a Botanical link alone does not make
all its patterns approved. The module index in `SKILL.md` is a catalog, not a redesign reading list.

| Updated source                     | Coverage available for redesign                                                             |
| ---------------------------------- | ------------------------------------------------------------------------------------------- |
| Shared `design/SKILL.md`           | Review process, screen checks, accessibility, engineering and existing workflow constraints |
| Botanical starter guidance         | Demonstrated v3 visual foundations within its stated boundaries                             |
| `shell.md` — Sidebar section       | Variant 2 revision 2 sidebar appearance; see linked approval record for boundaries          |
| `shell.md` — Header/layout section | Header B revision 4 appearance and shared shell-body gutter; approval record owns scope     |
| Classic individual design modules  | Use only for untouched-screen maintenance                                                   |

When a needed pattern has no updated guidance, extend the approved Botanical foundations, research
its unresolved interaction and build it in the focused demo for Jafar’s review. Keep existing capabilities
and permissions through product contracts and implementation inspection. Leave older visual modules
unloaded for redesign work; preserve their useful nonvisual constraints in the updated guidance when
that pattern is reviewed. After approval, record the exact coverage here and update its Botanical module before
implementation. Approval of one pattern in a module does not approve the module’s remaining patterns.

## Established foundations

Botanical v3 establishes the visual direction for composition, colour roles, typography measurements,
spacing examples, surfaces, radii, borders, subtle shadows, populated panels, selected navigation,
illustrated status badges and primary-button default/hover appearance. These are reference foundations,
not a complete component system or approval of every interaction. Inter rendering is unverified.

Relevant Classic modules: `brand.md`, `colors.md`, `typography.md`, `layout.md`, `content.md`,
`radius.md`, `shadows.md`, `borders.md`, `cards.md`, `section-block.md`, `icon-shapes.md`,
`buttons.md`, `badges.md`, `status-indicators.md`, `stats-cards.md` and `data-display.md` if added.
Their old visual specifications serve untouched surfaces; use the starter guidance for demonstrated
Botanical foundations. Update component-specific rules when that component's focused approval exists.

## Awaiting focused design and approval

| Coverage                                                         | Relevant Classic modules                                                          | Approval boundary                                                                                                                |
| ---------------------------------------------------------------- | --------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| Header and supporting controls                                   | `layout.md`, `avatars.md`, `dropdown.md`                                          | Shell header B revision 4 approved; `shell.md` aligned. Universal menus, account patterns and dialogs still await focused review |
| Forms, validation, save/cancel appearance and selection controls | `inputs.md`, `radios-checkboxes-toggle.md`, `button-group.md`, `buttons.md`       | Preserve current save/cancel behavior; review new appearance and states                                                          |
| Dialogs, menus, tooltips, popovers and lightbox                  | `modals.md`, `dropdown.md`, `tooltips-popovers.md`                                | Illustrative v3 editors/previews do not establish the complete system                                                            |
| Tabs, accordions, lists, financial tables and pagination         | `tabs.md`, `accordion.md`, `lists.md`, `tables.md`, `pagination.md`, `content.md` | A captured section strip or table does not approve all states or narrow layouts                                                  |
| Alerts, empty/loading/error states, disabled/loading actions     | `alerts.md`, `buttons.md`, affected component modules                             | Require affected states in focused demos                                                                                         |
| Calendars, scheduling controls, charts and timelines             | Relevant existing components; add guidance only as needed                         | No complete Botanical pattern established                                                                                        |
| Dark mode, customer-facing and industry-specific layouts         | `colors.md`, relevant layout/component modules                                    | Separate focused review; no approval inferred from old modules                                                                   |
| Long content, text resizing, contrast and outdoor readability    | All affected modules                                                              | Verify in each focused demo; baseline captures are not accessibility proof                                                       |

## Updating after approval

Record the demo revision, portion, states, date and exclusions in permanent guidance or its linked
approval record. Update the relevant Botanical module to link shared foundations and describe the newly
approved pattern; preserve useful behavior/accessibility rules. Mark only that coverage established here.
Review shared effects on previously migrated screens before implementation. Keep remaining gaps visible.
