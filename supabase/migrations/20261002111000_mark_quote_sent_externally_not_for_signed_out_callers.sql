-- Pipeline upgrade B3. Supabase's default privileges hand every new public function to `anon` as well.
-- `mark_quote_sent_externally` refuses a caller with no identity anyway (`publish_quote` checks
-- `quotes.send`), but a signed-out visitor has no business reaching it at all — the same grants
-- `publish_quote` itself carries.
revoke all on function public.mark_quote_sent_externally(uuid, integer, text, text) from anon;
