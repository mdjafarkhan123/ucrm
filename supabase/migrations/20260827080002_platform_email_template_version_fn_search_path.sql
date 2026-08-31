create or replace function private.bump_platform_email_template_version()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.subject is distinct from old.subject or new.body is distinct from old.body then
    new.version := old.version + 1;
  end if;
  return new;
end;
$$;
