begin;
set local search_path=public,extensions;
select no_plan();
select is((select furnishings_category_id from public.spike_accounts where id='account-primary'),null::text,
 'An unresolved Account does not guess Furnishings from its name');
select lives_ok($$update public.spike_accounts set furnishings_category_id='category-furnishings' where id='account-primary'$$,
 'Trusted setup binds an exact Account-scoped category');
select throws_ok($$update public.spike_accounts set furnishings_category_id='category-furnishings' where id='account-other'$$,
 '23503',null,'A foreign Account cannot adopt this category');
select throws_ok($$update public.spike_accounts set furnishings_category_id=null where id='account-primary'$$,
 '55000',null,'Clearing identity cannot silently unclassify Item accounting');
select throws_ok($$update public.spike_accounts set furnishings_category_id='other' where id='account-primary'$$,
 '55000',null,'Changing defaults cannot repoint canonical Furnishings');
select ok(not has_column_privilege('authenticated','public.spike_accounts','furnishings_category_id','UPDATE'),
 'Ordinary client writes cannot assign canonical identity');
select * from finish();
rollback;
