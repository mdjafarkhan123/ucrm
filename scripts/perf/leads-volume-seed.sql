-- Jafar business B1: 20,000 fake Leads with 1-3 contact methods each, for timing the Leads list.
-- Practice database only (Docker supabase_db_ucrm). Never run against the live project.
begin;
insert into public.platform_business_relationships (
  business_name, country_code, trade, source, website, contact_name, fit_notes, lead_status,
  next_action, next_action_due_on, created_by_email, created_at
)
select
  'Volume Trade ' || g || ' ' || (array['Plumbing','Roofing','Electric','HVAC','Landscapes','Painters'])[1 + g % 6],
  (array['GB','US','CA','AU','IE','NZ','DE','FR','ZA','NL','ES','IT'])[1 + (g * 7) % 12],
  (array['Plumbing','Roofing','Electrical','HVAC','Landscaping','Painting'])[1 + g % 6],
  (array['own_website','google_maps','directory','social','referral','contacted_us','event','other'])[1 + (g * 3) % 8],
  case when g % 5 <> 0 then 'https://www.volume-trade-' || g || '.example.com' end,
  case when g % 3 = 0 then 'Owner ' || g end,
  case when g % 4 = 0 then 'Fit notes for lead ' || g end,
  (array['new','researching','ready_for_review','unsuitable','later'])[1 + (g * 11) % 5],
  case when g % 2 = 0 then 'Follow up ' || g end,
  case when g % 2 = 0 then current_date + ((g % 60) - 30) end,
  'dev.jafarkhan@gmail.com',
  now() - (g || ' minutes')::interval
from generate_series(1, 20000) g;

insert into public.platform_business_contact_methods (relationship_id, kind, value, found_at, position)
select r.id, k.kind,
  case k.kind when 'email' then 'info' || r.n || '@volume-trade.example.com'
              when 'phone' then '+44 7700 ' || lpad((r.n % 1000000)::text, 6, '0')
              else '@volume' || r.n end,
  'Their website', k.pos
from (select id, row_number() over (order by created_at) as n from public.platform_business_relationships
      where created_by_email = 'dev.jafarkhan@gmail.com' and business_name like 'Volume Trade %') r
cross join lateral (
  select * from (values ('email', 0), ('phone', 1), ('instagram', 2)) v(kind, pos) where v.pos <= r.n % 3
) k;
commit;
analyze public.platform_business_relationships;
analyze public.platform_business_contact_methods;
