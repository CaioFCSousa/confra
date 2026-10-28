-- Rode este arquivo se o 01_schema.sql JÁ foi executado no Supabase antes.
-- Troca os tamanhos do abadá para M/G e GG/XG.
update public.config set tamanhos = '{M/G,GG/XG}' where id = 1;

create or replace view public.resumo_abadas with (security_invoker = true) as
  select tamanho, count(*) as quantidade
    from public.respostas where disponibilidade = 'Sim'
   group by tamanho order by array_position(array['M/G','GG/XG'], tamanho);
