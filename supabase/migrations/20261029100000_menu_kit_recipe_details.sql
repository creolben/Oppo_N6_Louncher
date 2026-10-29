-- Recipe details printed on each recipe page: the paragraph introducing the
-- dish, the times on the "Serves:" line, the numbered instructions and the
-- per-serving nutrition.

alter table public.menu_kit_recipes
  add column description text,
  add column prep_minutes smallint check (prep_minutes >= 0),
  add column cook_minutes smallint check (cook_minutes >= 0),
  -- Marinating or resting time.
  add column rest_minutes smallint check (rest_minutes >= 0),
  add column steps text[] not null default '{}',
  add column nutrition jsonb check (jsonb_typeof(nutrition) = 'object');

comment on column public.menu_kit_recipes.nutrition is
  'Per serving, as printed, keyed by nutrient and unit: {"calories_kcal": 349, "protein_g": 18.8, "sodium_mg": 196, "iron_pct": 35}. Null when the page prints none.';

-- Same as in 20261028150000_menu_kits.sql, plus the recipe details.
create or replace function public.ingest_menu_kit(kit jsonb)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
<<ingest>>
declare
  kit_id uuid;
  week date := nullif(kit ->> 'week_start', '')::date;
  recipe jsonb;
  recipe_id uuid;
  recipe_ids uuid[] := '{}';
begin
  if coalesce(kit ->> 'title', '') = '' then
    raise exception 'ingest_menu_kit: title is required';
  end if;
  if jsonb_array_length(coalesce(kit -> 'items', '[]')) = 0 then
    raise exception 'ingest_menu_kit: a kit needs at least one shopping-list item';
  end if;

  select m.id into kit_id
  from public.menu_kits m
  where m.pdf_sha256 = kit ->> 'pdf_sha256'
     or (m.title = kit ->> 'title' and m.week_start = week)
  order by (m.pdf_sha256 = kit ->> 'pdf_sha256') desc
  limit 1;

  if kit_id is null then
    insert into public.menu_kits
      (title, week_label, week_start, place, source_file, pdf_sha256, pdf_path)
    values (
      kit ->> 'title', kit ->> 'week_label', week, kit ->> 'place',
      kit ->> 'source_file', kit ->> 'pdf_sha256', kit ->> 'pdf_path'
    )
    returning id into kit_id;
  else
    update public.menu_kits m set
      title = kit ->> 'title',
      week_label = kit ->> 'week_label',
      week_start = week,
      place = kit ->> 'place',
      source_file = kit ->> 'source_file',
      pdf_sha256 = kit ->> 'pdf_sha256',
      pdf_path = kit ->> 'pdf_path',
      imported_at = now()
    where m.id = ingest.kit_id;
    delete from public.menu_kit_dishes d where d.kit_id = ingest.kit_id;
    delete from public.menu_kit_items i where i.kit_id = ingest.kit_id;
  end if;

  insert into public.menu_kit_dishes (kit_id, variant, day, position, dish)
  select ingest.kit_id, d ->> 'variant', d ->> 'day',
         (dish.ordinality - 1)::smallint, dish.value
  from jsonb_array_elements(coalesce(kit -> 'menus', '[]')) d,
       jsonb_array_elements_text(d -> 'dishes') with ordinality dish;

  insert into public.menu_kit_items (
    kit_id, variant, position, name, aisle, amount_text, quantity_amount,
    quantity_unit, note, cost_cents, days, pantry
  )
  select ingest.kit_id, i ->> 'variant', (i ->> 'position')::smallint,
         i ->> 'name', i ->> 'aisle', i ->> 'amount_text',
         (i ->> 'quantity_amount')::numeric, i ->> 'quantity_unit', i ->> 'note',
         (i ->> 'cost_cents')::integer,
         array(select jsonb_array_elements_text(coalesce(i -> 'days', '[]'))),
         coalesce((i ->> 'pantry')::boolean, false)
  from jsonb_array_elements(kit -> 'items') i;

  for recipe in select * from jsonb_array_elements(coalesce(kit -> 'recipes', '[]'))
  loop
    insert into public.menu_kit_recipes (
      kit_id, position, title, servings, side, variants, description,
      prep_minutes, cook_minutes, rest_minutes, steps, nutrition
    )
    values (
      ingest.kit_id, (recipe ->> 'position')::smallint,
      recipe ->> 'title', (recipe ->> 'servings')::smallint,
      coalesce((recipe ->> 'side')::boolean, false),
      array(select jsonb_array_elements_text(recipe -> 'variants')),
      recipe ->> 'description',
      (recipe ->> 'prep_minutes')::smallint,
      (recipe ->> 'cook_minutes')::smallint,
      (recipe ->> 'rest_minutes')::smallint,
      array(select jsonb_array_elements_text(coalesce(recipe -> 'steps', '[]'))),
      nullif(recipe -> 'nutrition', 'null'::jsonb)
    )
    on conflict on constraint menu_kit_recipes_kit_id_title_key do update set
      position = excluded.position,
      servings = excluded.servings,
      side = excluded.side,
      variants = excluded.variants,
      description = excluded.description,
      prep_minutes = excluded.prep_minutes,
      cook_minutes = excluded.cook_minutes,
      rest_minutes = excluded.rest_minutes,
      steps = excluded.steps,
      nutrition = excluded.nutrition
    returning id into recipe_id;

    recipe_ids := recipe_ids || recipe_id;
    delete from public.menu_kit_recipe_ingredients ri
    where ri.recipe_id = ingest.recipe_id;

    insert into public.menu_kit_recipe_ingredients
      (recipe_id, position, name, quantity_amount, quantity_unit, note)
    select ingest.recipe_id, (g.ordinality - 1)::smallint,
           g.value ->> 'name', (g.value ->> 'quantity_amount')::numeric,
           g.value ->> 'quantity_unit', g.value ->> 'note'
    from jsonb_array_elements(coalesce(recipe -> 'ingredients', '[]'))
         with ordinality g;
  end loop;

  delete from public.menu_kit_recipes r
  where r.kit_id = ingest.kit_id and r.id <> all (recipe_ids);

  return kit_id;
end;
$$;
