-- Aviary: public views, lineage profile RPC, lines carried, family tree
-- Run after parrot_schema.sql (part 2 of 2)

-- ─── Public bird list (limited columns; bypasses birds RLS for anon) ────────

create or replace view public_birds
with (security_invoker = false)
as
select
  id,
  name,
  species,
  sex,
  hatch_date,
  phenotype,
  genotype,
  status,
  origin_description,
  bred_by,
  line_name,
  video_url
from birds;

grant select on public_birds to anon, authenticated;

-- Block direct reads of sensitive bird rows from anon
create policy birds_deny_anon on birds
  for select to anon using (false);

-- ─── Helpers ────────────────────────────────────────────────────────────────

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
      phenotype, genotype, status, origin_description,
      bred_by, line_name, video_url
    from birds where id = p_id
  ) b;
$$;

create or replace function lines_carried_for_bird(p_bird uuid)
returns text[]
language sql
stable
security definer
set search_path = public
as $$
  with recursive anc as (
    select id, line_name, father_id, mother_id, 0 as depth
    from birds where id = p_bird
    union all
    select b.id, b.line_name, b.father_id, b.mother_id, a.depth + 1
    from birds b
    join anc a on b.id in (a.father_id, a.mother_id)
    where a.depth < 4
  ),
  own as (
    select line_name from birds where id = p_bird and line_name is not null and btrim(line_name) <> ''
  )
  select coalesce(
    (select array[line_name] from own),
    (select array_agg(distinct line_name order by line_name)
     from anc
     where line_name is not null and btrim(line_name) <> '')
  );
$$;

create or replace function pairing_block_json(
  p_male uuid,
  p_female uuid,
  p_pairing_id uuid default null
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'father', bird_public_json(p_male),
    'mother', bird_public_json(p_female),
    'lines_cross', (
      select jsonb_build_object(
        'father_line', fm.line_name,
        'mother_line', ff.line_name,
        'combined', coalesce((
          select jsonb_agg(distinct ln order by ln)
          from (
            select nullif(btrim(x.ln), '') as ln
            from (values (fm.line_name), (ff.line_name)) as x(ln)
            where x.ln is not null and btrim(x.ln) <> ''
          ) q
        ), '[]'::jsonb)
      )
      from birds fm, birds ff
      where fm.id = p_male and ff.id = p_female
    ),
    'chicks', coalesce((
      select jsonb_agg(
        bird_public_json(b.id) || jsonb_build_object(
          'clutch', coalesce(c.label, to_char(c.laid_on, 'YYYY-MM-DD'), 'Chicks')
        )
        order by c.laid_on nulls last, b.name
      )
      from birds b
      join clutches c on c.id = b.clutch_id
      where b.father_id = p_male
        and b.mother_id = p_female
        and (p_pairing_id is null or c.pairing_id = p_pairing_id)
    ), '[]'::jsonb)
  );
$$;

-- ─── Public bird page payload ───────────────────────────────────────────────

create or replace function public_bird_profile(p_bird uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  b birds%rowtype;
  desc_text text;
  hist jsonb;
  origin jsonb;
  current_blk jsonb;
  past jsonb;
  pr pairings%rowtype;
begin
  select * into b from birds where id = p_bird;
  if not found then
    return null;
  end if;

  desc_text := trim(both from concat_ws(
    '. ',
    case when b.bred_by is not null and b.bred_by <> '' then 'Bred by ' || b.bred_by else null end,
    nullif(b.origin_description, '')
  ));
  if desc_text = '' then
    desc_text := null;
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'name', h.person_name,
      'role', h.role,
      'from_year', h.from_year,
      'to_year', h.to_year,
      'notes', h.notes
    )
    order by h.sort_order, h.from_year nulls last
  ), '[]'::jsonb)
  into hist
  from bird_history h
  where h.bird_id = p_bird and h.show_publicly;

  if b.father_id is not null and b.mother_id is not null then
    origin := pairing_block_json(b.father_id, b.mother_id, null);
  else
    origin := null;
  end if;

  select * into pr
  from pairings
  where ended_on is null
    and p_bird in (male_id, female_id)
  order by started_on desc nulls last
  limit 1;

  if found then
    current_blk := pairing_block_json(pr.male_id, pr.female_id, pr.id);
  else
    current_blk := null;
  end if;

  select coalesce(jsonb_agg(
    pairing_block_json(p.male_id, p.female_id, p.id)
    order by p.ended_on desc nulls last
  ), '[]'::jsonb)
  into past
  from pairings p
  where p.ended_on is not null
    and p.show_after_end
    and p_bird in (p.male_id, p.female_id)
    and (pr.id is null or p.id <> pr.id);

  return jsonb_build_object(
    'bird', bird_public_json(p_bird),
    'description', desc_text,
    'lines_carried', coalesce(to_jsonb(lines_carried_for_bird(p_bird)), '[]'::jsonb),
    'history', hist,
    'origin', origin,
    'current_pairing', current_blk,
    'past_pairings', past
  );
end;
$$;

grant execute on function public_bird_profile(uuid) to anon, authenticated;
grant execute on function bird_public_json(uuid) to authenticated;
grant execute on function lines_carried_for_bird(uuid) to authenticated;
grant execute on function pairing_block_json(uuid, uuid, uuid) to authenticated;

-- ─── Full family tree (for future admin tooling) ────────────────────────────

create or replace function family_tree(p_root uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  b birds%rowtype;
  children jsonb;
  pairings_json jsonb;
begin
  select * into b from birds where id = p_root;
  if not found then
    return null;
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'bird', bird_public_json(c.id),
      'clutch_id', c.clutch_id
    )
    order by c.name
  ), '[]'::jsonb)
  into children
  from birds c
  where c.father_id = p_root or c.mother_id = p_root;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'pairing_id', p.id,
      'male_id', p.male_id,
      'female_id', p.female_id,
      'started_on', p.started_on,
      'ended_on', p.ended_on,
      'block', pairing_block_json(p.male_id, p.female_id, p.id)
    )
    order by p.started_on nulls last
  ), '[]'::jsonb)
  into pairings_json
  from pairings p
  where p_root in (p.male_id, p.female_id);

  return jsonb_build_object(
    'bird', bird_public_json(p_root),
    'parents', jsonb_build_object(
      'father', case when b.father_id is not null then bird_public_json(b.father_id) end,
      'mother', case when b.mother_id is not null then bird_public_json(b.mother_id) end
    ),
    'children', children,
    'pairings', pairings_json
  );
end;
$$;

grant execute on function family_tree(uuid) to authenticated;
