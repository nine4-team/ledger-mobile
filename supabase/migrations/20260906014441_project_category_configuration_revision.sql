alter table public.spike_projects
  add column category_configuration_revision numeric not null default 1,
  add constraint spike_projects_category_configuration_revision_check
    check (
      scale(category_configuration_revision) = 0
      and category_configuration_revision >= 1::numeric
      and category_configuration_revision <= 18446744073709551615::numeric
    );

comment on column public.spike_projects.category_configuration_revision is
  'Independent complete Project category-configuration generation; never derived from Project or allocation-row revisions.';
