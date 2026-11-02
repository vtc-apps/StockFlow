-- ═══════════════════════════════════════════════════════════════════════
--  VTC PGIM · Clear the product master (run once in Supabase → SQL Editor)
--
--  Deletes every product that has NO inward / dispatch / transfer entry.
--  Products that are used by an entry are kept, so stock can never break.
--  Adds a record to the Change Log. Run "Download backup" in the app first.
-- ═══════════════════════════════════════════════════════════════════════

begin;

alter table public.products disable trigger sf_no_delete;

with gone as (
  delete from public.products p
   where not exists (
     select 1 from public.transactions t where t.data->>'productId' = p.id
   )
  returning p.id
), n as (select count(*) as c from gone)
insert into public.change_log (id, data)
select 'log-clear-products-' || extract(epoch from now())::bigint,
       jsonb_build_object(
         'id', 'log-clear-products-' || extract(epoch from now())::bigint,
         'at', (extract(epoch from now()) * 1000)::bigint,
         'by', 'admin',
         'action', 'delete',
         'entity', 'product',
         'entityId', 'all',
         'label', 'Product master cleared',
         'changes', jsonb_build_array(jsonb_build_object('field', 'Products deleted', 'from', n.c::text, 'to', 'Deleted'))
       )
  from n;

alter table public.products enable trigger sf_no_delete;

commit;

-- What is left (should be 0 unless some products are used by entries):
select count(*) as products_left from public.products;
