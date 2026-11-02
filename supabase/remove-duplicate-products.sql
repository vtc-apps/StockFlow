-- VTC PGIM · remove duplicate products (run once in Supabase → SQL Editor)
-- Deletes only product copies that PGIM has already merged into another
-- product (marked "mergedInto") and that no entry uses. Nothing else is touched,
-- and the no-delete protection is switched back on at the end.

begin;
alter table public.products disable trigger sf_no_delete;

delete from public.products p
 where p.data ? 'mergedInto'
   and not exists (select 1 from public.transactions t where t.data->>'productId' = p.id);

alter table public.products enable trigger sf_no_delete;
commit;

-- Check: should show each product name + brand only once
select data->>'name' as product, data->>'brand' as brand, count(*) as copies
  from public.products
 group by 1, 2
having count(*) > 1;
