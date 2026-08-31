-- performance-review gate: cover the two foreign keys the advisor flagged as unindexed.
create index website_chat_widgets_updated_by_idx
  on public.website_chat_widgets (updated_by)
  where updated_by is not null;

create index website_chat_widget_origins_created_by_idx
  on public.website_chat_widget_origins (created_by)
  where created_by is not null;
