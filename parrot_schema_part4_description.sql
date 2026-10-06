-- Profile description = origin story only (bred_by stays in its own field)

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

  desc_text := nullif(trim(both from coalesce(b.origin_description, '')), '');

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
