-- Hide ring numbers from public API; expose line names and pairing-line crosses
-- Run after parrot_schema_part2.sql

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
  phenotype,
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
      phenotype, status, origin_description,
      bred_by, line_name, video_url
    from birds where id = p_id
  ) b;
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
