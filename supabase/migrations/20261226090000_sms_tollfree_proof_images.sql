-- Carrier proof pictures stay in private R2. A random public token gives Twilio a durable HTTPS
-- read link; only the owning business can upload or remove the picture through the application.
create table public.communication_sms_tollfree_proof_images (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  verification_id uuid not null,
  public_token uuid not null default gen_random_uuid() unique,
  object_key text not null unique,
  mime_type text not null check (mime_type in ('image/jpeg', 'image/png')),
  file_name text not null check (char_length(file_name) between 1 and 140),
  size_bytes integer not null check (size_bytes between 1 and 5242880),
  created_at timestamptz not null default now(),
  constraint communication_sms_tollfree_proof_images_check_fkey
    foreign key (organization_id, verification_id)
    references public.communication_sms_tollfree_verifications (organization_id, id) on delete cascade
);

create index communication_sms_tollfree_proof_images_check_idx
  on public.communication_sms_tollfree_proof_images (verification_id, created_at);

alter table public.communication_sms_tollfree_proof_images enable row level security;
revoke all on public.communication_sms_tollfree_proof_images from anon, authenticated;
