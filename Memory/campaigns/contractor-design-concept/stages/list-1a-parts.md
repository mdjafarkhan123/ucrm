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
| `layout/SectionBlock` |  | ✅ Page parts board `j3jDI` | ✅ Merged 2026-10-19 |
| `layout/PageContainer` |  | ✅ Page parts board `j3jDI` | ✅ Merged 2026-10-19 |
| `layout/PageHeader` |  | ✅ | ✅ |
| `ui/Badge` |  | ✅ Fields board `khuNF` | ✅ 2026-10-19 |
| `ui/Dialog` |  | ✅ Pop-ups board `v2Y89` | ✅ 2026-10-19 |
| `ui/Textarea` |  | ✅ Fields board `khuNF` | ✅ 2026-10-19 |
| `ui/SearchInput` |  | ✅ Fields board `khuNF` | ✅ 2026-10-19 |
| `ui/DropdownMenu` |  | ✅ | ✅ |
| `layout/Breadcrumbs` |  | ✅ Page parts board `j3jDI` | ✅ Merged 2026-10-19 |
| `ui/ConfirmDialog` |  | ✅ Pop-ups board `v2Y89` | ✅ 2026-10-19 |
| `ui/SegmentedControl` |  | ✅ | ✅ |
| `ui/StatusBadge` |  | ✅ | ✅ Merged 2026-10-19 |
| `layout/StickyActionBar` |  | ✅ | ✅ |
| `ui/Avatar` |  | ✅ Small controls `GbgcY` | ⬜ |
| `data-display/ListLoadMore` |  | ✅ Batch 7 `eJ0QQ` | ⬜ |
| `ui/CalendarPicker` |  | ✅ Pickers v2 `uSXlT` | ⬜ |
| `data-display/DataTable` |  | ⬜ | ⬜ |
| `forms/FormErrorSummary` |  | ✅ Batch 7 `eJ0QQ` | ⬜ |
| `layout/RecordFormLayout` |  | ✅ | ✅ |
| `layout/RailCard` |  | ✅ Page parts board `j3jDI` | ✅ Merged 2026-10-19 |
| `ui/Banner` |  | ✅ Page parts board `j3jDI` | ✅ Merged 2026-10-19 |
| `ui/Lightbox` |  | ✅ Batch 8 `b4BxuV` | ⬜ |
| `ui/TimePickerField` |  | ✅ Pickers v2 `uSXlT` | ⬜ |
| `ui/Toggle` |  | ✅ Small controls `GbgcY` | ⬜ |
| `files/FileThumb` |  | ✅ Batch 8 `b4BxuV` | ⬜ |
| `ui/Card` |  | ✅ | ✅ Merged 2026-10-19 |
| `ui/CardHeader` | Pencil "Card header"; on every Home card so far | ✅ | ✅ |
| `ui/TimePicker` |  | ✅ Pickers v2 `uSXlT` | ⬜ |
| `ui/PencilButton` |  | ✅ Batch 7 `eJ0QQ` | ⬜ |
| `forms/MoneyInput` |  | ✅ Inputs and chips `Fma1f` | ✅ 2026-10-19 |
| `ui/FilterChip` |  | ✅ Inputs and chips `Fma1f` | ✅ 2026-10-19 |
| `data-display/KpiCard` |  | ✅ Batch 7 `eJ0QQ` | ⬜ |
| `layout/SidePanel` |  | ✅ Pop-ups board `v2Y89` | ✅ 2026-10-19 |
| `ui/DateTimePicker` |  | ✅ Pickers v2 `uSXlT` | ⬜ |
| `ui/CountryPicker` |  | ✅ Pickers v2 `uSXlT` | ⬜ |
| `ui/TagSelect` |  | ✅ Inputs and chips `Fma1f` | ✅ 2026-10-19 |
| `collaboration/AttachmentSurface` |  | ✅ Batch 9 `KuOmH` | ⬜ |
| `data-display/RecordListCard` |  | 🔁 Jobs list card `t8ULdJ` | ⬜ |
| `files/PhotoSlot` |  | ✅ Batch 8 `b4BxuV` | ⬜ |
| `quotes/CatalogItemDialog` | 🔁F pop-up · loading, permission-limited, field-worker view | ✅ Batch 10 `ZWTSi` | ⬜ |
| `ui/TabPanel` |  | ⬜ | ⬜ |
| `ui/Tabs` | tabs ×2 | ✅ Small controls `GbgcY` | ⬜ |
| `forms/QuantityInput` |  | ✅ Inputs and chips `Fma1f` | ✅ 2026-10-19 |
| `quotes/CatalogItemPicker` | loading | ✅ Batch 10 `ZWTSi` | ⬜ |
| `quotes/PriceBookDrawer` | 🔁D pop-up · loading, empty, permission-limited, field-worker view | ✅ Batch 10 `ZWTSi` | ⬜ |
| `quotes/ProductsAndServicesBlock` | pop-ups: "Throw away these changes?" 🔁C · menus ×1 · empty, permission-limited, field-worker view | ⬜ | ⬜ |
| `ui/RadioGroup` |  | ✅ Small controls `GbgcY` | ⬜ |
| `ui/TimezonePicker` |  | ✅ Pickers v2 `uSXlT` | ⬜ |
| `work/ClientPicker` | loading | ✅ | ✅ |
| `time-clock/RunningClock` |  | ⬜ | ⬜ |
| `time-clock/TimerElapsed` |  | ⬜ | ⬜ |
| `files/FileUploader` |  | ✅ Batch 8 `b4BxuV` | ⬜ |
| `layout/DetailEditBar` |  | 🔁 Save bar in `jFBRB` | ⬜ |
| `layout/RecordDetailLayout` |  | ⬜ | ⬜ |
| `work/MoneyFeatureCard` |  | ✅ | ✅ |
| `work/QuickContactButtons` |  | 🔁 Job details header `tNdkX` | ⬜ |
| `clients/ClientTagSelect` |  | ⬜ | ⬜ |
| `collaboration/AuthorMeta` |  | ✅ Batch 9 `KuOmH` | ⬜ |
| `collaboration/NoteBody` |  | ✅ Batch 9 `KuOmH` | ⬜ |
| `collaboration/NoteFiles` |  | ✅ Batch 9 `KuOmH` | ⬜ |
| `files/FileLabelsDialog` | 🔁F pop-up · pop-ups: "confirm" 🔁C · loading | ⬜ | ⬜ |
| `files/FilePicker` | pop-ups: "You do not have access to the file library" 🔁F · loading, empty, permission-limited | ⬜ | ⬜ |
| `files/PendingFilesCard` |  | ✅ Batch 9 `KuOmH` | ⬜ |
| `files/PhotoDescribeForm` | loading, permission-limited | ⬜ | ⬜ |
| `work/ClientSummaryCard` | menus ×1 | 🔁 Job details client box `tNdkX` | ⬜ |
