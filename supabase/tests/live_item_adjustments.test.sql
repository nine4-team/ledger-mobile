begin;
set local search_path=public,extensions;
select plan(17);
select is(ledger_private.calculate_item_adjustments(1,-1,
 '[{"itemId":"a","numerator":"18446744073709551614","denominator":"1"}]')->>'differenceNumerator',null,'unadjusted overflow makes Difference unknown');
select is(ledger_private.calculate_item_adjustments(1,-1,
 '[{"itemId":"a","numerator":"18446744073709551614","denominator":"1"}]')->'items'->0->>'issue','arithmeticRange','unadjusted overflow cannot yield apparently valid prices');
select is(ledger_private.calculate_item_adjustments(2,1,
 '[{"itemId":"a","numerator":"1","denominator":"2"},{"itemId":"b","numerator":"1","denominator":"2"}]')->'items'->0->>'unadjustedMinorUnits','1','stable allocated display uses price minus share');
select ok((select bool_and((item->>'unadjustedMinorUnits')::bigint+(item->>'adjustmentsMinorUnits')::bigint=(item->>'projectPriceMinorUnits')::bigint)
 from jsonb_array_elements(ledger_private.calculate_item_adjustments(2,1,
 '[{"itemId":"a","numerator":"1","denominator":"2"},{"itemId":"b","numerator":"1","denominator":"2"}]')->'items') item),'every half-cent display reconciles');
select is(ledger_private.calculate_item_adjustments(2,1,
 '[{"itemId":"a","numerator":"49999999999999999999999999999999999998","denominator":"99999999999999999999999999999999999997"}]')->'items'->0->>'adjustmentsMinorUnits','0','near-half-cent rational never rounds through numeric division');
select is(ledger_private.calculate_item_adjustments(12000,2000,
 '[{"itemId":"a","numerator":"1000","denominator":"1"}]')->'items'->0->>'adjustmentsMinorUnits','200','partial Item uses whole-order base');
select is(ledger_private.calculate_item_adjustments(12000,2000,
 '[{"itemId":"a","numerator":"1000","denominator":"1"}]')->>'isProvisional','true','partial is provisional');
select is(ledger_private.calculate_item_adjustments(12000,2000,
 '[{"itemId":"a","numerator":"1000","denominator":"1"},{"itemId":"b","numerator":"9000","denominator":"1"}]')->>'isBalanced','true','exact balance');
select is(ledger_private.item_price_inverse(1,3,1)->>'numerator','2','inverse numerator preserved');
select is(ledger_private.item_price_inverse(1,3,1)->>'denominator','3','repeating inverse not rounded');
select is(ledger_private.item_price_inverse(100,20,20)->>'issue','nonpositiveBase','invalid base retains calculation issue');
select is(ledger_private.item_price_inverse(100,0,-20)->>'issue','zeroFactor','zero factor explains nonzero intent');
select is(ledger_private.item_price_inverse(100,20,20)->>'requestedProjectPriceMinorUnits','100','invalid calculation retains intent');
select is(ledger_private.calculate_item_adjustments(3,1,
 '[{"itemId":"c","numerator":"2","denominator":"3"},{"itemId":"a","numerator":"2","denominator":"3"},{"itemId":"b","numerator":"2","denominator":"3"}]')->'items'->1->>'adjustmentsMinorUnits','1','stable identity receives positive penny');
select is(ledger_private.calculate_item_adjustments(2,-1,
 '[{"itemId":"c","numerator":"1","denominator":"1"},{"itemId":"a","numerator":"1","denominator":"1"},{"itemId":"b","numerator":"1","denominator":"1"}]')->'items'->1->>'adjustmentsMinorUnits','-1','stable identity receives negative penny');
select is(ledger_private.calculate_item_adjustments(4,1,
 '[{"itemId":"a","numerator":"3","denominator":"2"},{"itemId":"b","numerator":"3","denominator":"2"}]')->'items'->0->>'projectPriceMinorUnits','2','inclusive half-cent input round trips');
select is(ledger_private.calculate_item_adjustments(120,20,'[{"itemId":"a"}]')->>'differenceNumerator',null,'unknown evidence is not zero');
select * from finish();
rollback;
