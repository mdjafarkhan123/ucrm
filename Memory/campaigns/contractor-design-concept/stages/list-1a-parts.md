# Redesign checklist — tier 1 (a)

Key, tick rule and coverage command: `list-index.md`.

## Shared parts, most used first

| Piece | Inside it | Pencil | Built |
| --- | --- | --- | --- |
| `ui/Button` |  | ✅ | ✅ |
| `data-display/LoadingSkeleton` |  | ✅ Pop-ups board `v2Y89` | ✅ 2026-10-19 |
| `data-display/ErrorState` |  | ✅ Pop-ups board `v2Y89` | ✅ 2026-10-19 |
| `ui/Input` |  | ✅ Fields board `khuNF` | ✅ 2026-10-19 |
| `ui/Select` |  | ✅ Fields board `khuNF` | ✅ 2026-10-19 |
| `ui/Checkbox` |  | ✅ | ✅ |
| `data-display/EmptyState` |  | ✅ Pop-ups board `v2Y89` | ✅ 2026-10-19 |
| `layout/SectionBlock` |  | ✅ Page parts board `j3jDI` | ⬜ |
| `layout/PageContainer` |  | ✅ Page parts board `j3jDI` | ⬜ |
| `layout/PageHeader` |  | ✅ | ✅ |
| `ui/Badge` |  | ✅ Fields board `khuNF` | ✅ 2026-10-19 |
| `ui/Dialog` |  | ✅ Pop-ups board `v2Y89` | ✅ 2026-10-19 |
| `ui/Textarea` |  | ✅ Fields board `khuNF` | ✅ 2026-10-19 |
| `ui/SearchInput` |  | ✅ Fields board `khuNF` | ✅ 2026-10-19 |
| `ui/DropdownMenu` |  | ✅ | ✅ |
| `layout/Breadcrumbs` |  | ✅ Page parts board `j3jDI` | ⬜ |
| `ui/ConfirmDialog` |  | ✅ Pop-ups board `v2Y89` | ✅ 2026-10-19 |
| `ui/SegmentedControl` |  | ✅ | ✅ |
| `ui/StatusBadge` |  | ✅ | ⬜ |
| `layout/StickyActionBar` |  | ✅ | ✅ |
| `ui/Avatar` |  | ✅ Small controls `GbgcY` | ⬜ |
| `data-display/ListLoadMore` |  | ⬜ | ⬜ |
| `ui/CalendarPicker` |  | ✅ Pickers v2 `uSXlT` | ⬜ |
| `data-display/DataTable` |  | ⬜ | ⬜ |
| `forms/FormErrorSummary` |  | ⬜ | ⬜ |
| `layout/RecordFormLayout` |  | ✅ | ✅ |
| `layout/RailCard` |  | ✅ Page parts board `j3jDI` | ⬜ |
| `ui/Banner` |  | ✅ Page parts board `j3jDI` | ⬜ |
| `ui/Lightbox` |  | ⬜ | ⬜ |
| `ui/TimePickerField` |  | ✅ Pickers v2 `uSXlT` | ⬜ |
| `ui/Toggle` |  | ✅ Small controls `GbgcY` | ⬜ |
| `files/FileThumb` |  | ⬜ | ⬜ |
| `ui/Card` |  | ✅ | ⬜ |
| `ui/CardHeader` | Pencil "Card header"; on every Home card so far | ✅ | ✅ |
| `ui/TimePicker` |  | ✅ Pickers v2 `uSXlT` | ⬜ |
| `ui/PencilButton` |  | ⬜ | ⬜ |
| `forms/MoneyInput` |  | ⬜ | ⬜ |
| `ui/FilterChip` |  | ⬜ | ⬜ |
| `data-display/KpiCard` |  | ⬜ | ⬜ |
| `layout/SidePanel` |  | ✅ Pop-ups board `v2Y89` | ✅ 2026-10-19 |
| `ui/DateTimePicker` |  | ✅ Pickers v2 `uSXlT` | ⬜ |
| `ui/CountryPicker` |  | ✅ Pickers v2 `uSXlT` | ⬜ |
| `ui/TagSelect` |  | ⬜ | ⬜ |
| `collaboration/AttachmentSurface` |  | ⬜ | ⬜ |
| `data-display/RecordListCard` |  | ⬜ | ⬜ |
| `files/PhotoSlot` |  | ⬜ | ⬜ |
| `quotes/CatalogItemDialog` | 🔁F pop-up · loading, permission-limited, field-worker view | ⬜ | ⬜ |
| `ui/TabPanel` |  | ⬜ | ⬜ |
| `ui/Tabs` | tabs ×2 | ✅ Small controls `GbgcY` | ⬜ |
| `forms/QuantityInput` |  | ⬜ | ⬜ |
| `quotes/CatalogItemPicker` | loading | ⬜ | ⬜ |
| `quotes/PriceBookDrawer` | 🔁D pop-up · loading, empty, permission-limited, field-worker view | ⬜ | ⬜ |
| `quotes/ProductsAndServicesBlock` | pop-ups: "Throw away these changes?" 🔁C · menus ×1 · empty, permission-limited, field-worker view | ⬜ | ⬜ |
| `ui/RadioGroup` |  | ✅ Small controls `GbgcY` | ⬜ |
| `ui/TimezonePicker` |  | ✅ Pickers v2 `uSXlT` | ⬜ |
| `work/ClientPicker` | loading | ✅ | ✅ |
| `time-clock/RunningClock` |  | ⬜ | ⬜ |
| `time-clock/TimerElapsed` |  | ⬜ | ⬜ |
| `files/FileUploader` |  | ⬜ | ⬜ |
| `layout/DetailEditBar` |  | ⬜ | ⬜ |
| `layout/RecordDetailLayout` |  | ⬜ | ⬜ |
| `work/MoneyFeatureCard` |  | ✅ | ✅ |
| `work/QuickContactButtons` |  | ⬜ | ⬜ |
| `clients/ClientTagSelect` |  | ⬜ | ⬜ |
| `collaboration/AuthorMeta` |  | ⬜ | ⬜ |
| `collaboration/NoteBody` |  | ⬜ | ⬜ |
| `collaboration/NoteFiles` |  | ⬜ | ⬜ |
| `files/FileLabelsDialog` | 🔁F pop-up · pop-ups: "confirm" 🔁C · loading | ⬜ | ⬜ |
| `files/FilePicker` | pop-ups: "You do not have access to the file library" 🔁F · loading, empty, permission-limited | ⬜ | ⬜ |
| `files/PendingFilesCard` |  | ⬜ | ⬜ |
| `files/PhotoDescribeForm` | loading, permission-limited | ⬜ | ⬜ |
| `work/ClientSummaryCard` | menus ×1 | ⬜ | ⬜ |
