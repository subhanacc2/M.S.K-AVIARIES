-- Hide phenotype from public API (use origin story on profile; admin keeps full record)

drop view if exists public_birds;

create view public_birds
with (security_invoker = false)
as
select
  id,
  name,
  species,
  sex,
  hatch_date,
  status,
  origin_description,
  bred_by,
  line_name,
  video_url
from birds;

grant select on public_birds to anon, authenticated;

create or replace function bird_public_json(p_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select to_jsonb(b)
  from (
    select
      id, name, species, sex, hatch_date,
      status, origin_description,
      bred_by, line_name, video_url
    from birds where id = p_id
  ) b;
$$;
