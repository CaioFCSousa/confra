-- =====================================================================
-- CONFRATERNIZAÇÃO 2026 — banco no Supabase
-- Rode este arquivo inteiro em: Supabase > SQL Editor > New query > Run
-- Mesma lógica do Apps Script:
--   INTERNO  -> link avulso (/interno). Valida NOME + E-MAIL contra a tabela convidados
--   SEDUC    -> link avulso (/seduc). Só NOME COMPLETO (opcional: lista_seduc)
--   EXTERNO  -> 30 links únicos (/?t=TOKEN), uso único
-- O site só chama duas funções (obter_contexto e enviar_resposta).
-- As tabelas ficam fechadas (RLS sem políticas): ninguém lê/escreve direto pela internet.
-- =====================================================================

create extension if not exists unaccent with schema extensions;

-- ---------- Configuração (1 linha só; edite pelo Table Editor) ----------
create table if not exists public.config (
  id                  int primary key default 1 check (id = 1),
  tema                text        not null default 'MICARETA',
  data_evento         text        not null default '12/12/2026 (sábado)',
  prazo               timestamptz not null default '2026-11-10 23:59:59-03',
  prazo_texto         text        not null default '10 de novembro de 2026',
  dominios            text[]      not null default '{oros.com.br,vobys.com.br,trully.com.br}', -- vazio = qualquer domínio
  empresas            text[]      not null default '{OROS,VOBYS,TRULLY}',
  tamanhos            text[]      not null default '{M/G,GG/XG}',
  validar_lista_seduc boolean     not null default true
);
insert into public.config (id) values (1) on conflict (id) do nothing;

-- ---------- Convidados (internos e os 30 externos) ----------
create table if not exists public.convidados (
  id            bigserial primary key,
  tipo          text not null check (tipo in ('INTERNO', 'EXTERNO')),
  numero        int,                       -- nº do QR code (externos 1..30)
  token         text unique,               -- só externos
  nome          text,
  email         text,
  empresa       text,
  status        text not null default 'PENDENTE' check (status in ('PENDENTE', 'RESPONDIDO')),
  respondido_em timestamptz,
  criado_em     timestamptz not null default now()
);
create unique index if not exists convidados_email_interno
  on public.convidados (lower(email)) where tipo = 'INTERNO';

-- ---------- Lista SEDUC (opcional: se tiver nomes, só eles podem responder) ----------
create table if not exists public.lista_seduc (
  id   bigserial primary key,
  nome text not null
);

-- ---------- Respostas ----------
create table if not exists public.respostas (
  id              bigserial primary key,
  criado_em       timestamptz not null default now(),
  tipo            text not null,
  token           text,
  nome            text not null,
  email           text,
  empresa         text,
  disponibilidade text not null,
  tamanho         text
);

-- Tabelas fechadas para a internet (só as funções abaixo acessam)
alter table public.config      enable row level security;
alter table public.convidados  enable row level security;
alter table public.lista_seduc enable row level security;
alter table public.respostas   enable row level security;

-- ---------- Helpers ----------
create or replace function public.norm(t text) returns text
language sql stable set search_path = public, extensions as $$
  select lower(regexp_replace(trim(extensions.unaccent(coalesce(t, ''))), '\s+', ' ', 'g'));
$$;

-- ---------- 1) Contexto da página (o que mostrar para quem abriu o link) ----------
create or replace function public.obter_contexto(p_t text default null, p_f text default null)
returns json
language plpgsql security definer set search_path = public, extensions as $$
declare
  c    public.config;
  conv public.convidados;
  base jsonb;
  f    text := lower(coalesce(p_f, ''));
begin
  select * into c from public.config where id = 1;
  base := jsonb_build_object(
    'tema', c.tema, 'dataEvento', c.data_evento, 'prazoTexto', c.prazo_texto,
    'empresas', c.empresas, 'tamanhos', c.tamanhos);

  if now() > c.prazo then
    return base || '{"estado":"ENCERRADO"}';
  end if;

  if f = 'seduc'   then return base || '{"estado":"ABERTO","tipo":"SEDUC","token":""}'; end if;
  if f = 'interno' then return base || '{"estado":"ABERTO","tipo":"INTERNO","token":""}'; end if;

  if coalesce(p_t, '') = '' then return base || '{"estado":"INVALIDO"}'; end if;

  select * into conv from public.convidados where token = p_t and tipo = 'EXTERNO';
  if not found then return base || '{"estado":"INVALIDO"}'; end if;
  if conv.status = 'RESPONDIDO' then return base || '{"estado":"JA_RESPONDIDO"}'; end if;

  return base || jsonb_build_object('estado', 'ABERTO', 'tipo', 'EXTERNO', 'token', p_t);
end $$;

-- ---------- 2) Envio da resposta (toda a validação acontece aqui) ----------
create or replace function public.enviar_resposta(d json)
returns json
language plpgsql security definer set search_path = public, extensions as $$
declare
  c         public.config;
  conv      public.convidados;
  v_tipo    text := upper(coalesce(d->>'tipo', ''));
  v_nome    text := regexp_replace(trim(coalesce(d->>'nome', '')), '\s+', ' ', 'g');
  v_email   text := lower(trim(coalesce(d->>'email', '')));
  v_empresa text := upper(coalesce(d->>'empresa', ''));
  v_disp    text := case d->>'disponibilidade' when 'SIM' then 'Sim' when 'NAO' then 'Não' end;
  v_tam     text := upper(coalesce(d->>'tamanho', ''));
  v_token   text := null;
  partes    int;
begin
  select * into c from public.config where id = 1;

  if now() > c.prazo then return json_build_object('ok', false, 'msg', 'O prazo para preenchimento foi encerrado.'); end if;
  if v_disp is null then return json_build_object('ok', false, 'msg', 'Informe sua disponibilidade.'); end if;
  if v_disp = 'Sim' and not (v_tam = any (c.tamanhos)) then
    return json_build_object('ok', false, 'msg', 'Escolha o tamanho do abadá.');
  end if;

  select count(*) into partes from regexp_split_to_table(v_nome, ' ') p where length(p) >= 2;
  if partes < 2 or v_nome !~ '^[A-Za-zÀ-ÿ'' .-]+$' then
    return json_build_object('ok', false, 'msg', 'Informe seu nome completo (nome e sobrenome).');
  end if;

  if v_tipo = 'SEDUC' then
    perform pg_advisory_xact_lock(hashtext('seduc:' || norm(v_nome)));
    if c.validar_lista_seduc and exists (select 1 from public.lista_seduc)
       and not exists (select 1 from public.lista_seduc where norm(lista_seduc.nome) = norm(v_nome)) then
      return json_build_object('ok', false, 'msg', 'Nome não encontrado na lista de convidados da SEDUC. Confira a grafia do seu nome completo.');
    end if;
    if exists (select 1 from public.respostas r where r.tipo = 'SEDUC' and norm(r.nome) = norm(v_nome)) then
      return json_build_object('ok', false, 'msg', 'Já existe uma resposta registrada com este nome.');
    end if;
    v_email := null; v_empresa := null;

  elsif v_tipo = 'INTERNO' then
    if cardinality(c.dominios) > 0 and not (split_part(v_email, '@', 2) = any (c.dominios)) then
      return json_build_object('ok', false, 'msg', 'Use seu e-mail corporativo.');
    end if;
    if not (v_empresa = any (c.empresas)) then
      return json_build_object('ok', false, 'msg', 'Selecione a empresa.');
    end if;
    select * into conv from public.convidados
      where convidados.tipo = 'INTERNO' and lower(convidados.email) = v_email
      for update;
    if not found or norm(conv.nome) <> norm(v_nome) then
      return json_build_object('ok', false, 'msg', 'Nome ou e-mail não encontrados na lista de colaboradores. Confira os dados ou procure a organização.');
    end if;
    if conv.status = 'RESPONDIDO' then
      return json_build_object('ok', false, 'msg', 'Já existe uma resposta registrada para este e-mail.');
    end if;

  elsif v_tipo = 'EXTERNO' then
    v_token := d->>'token';
    select * into conv from public.convidados
      where convidados.token = v_token and convidados.tipo = 'EXTERNO'
      for update;
    if not found then return json_build_object('ok', false, 'msg', 'Link inválido.'); end if;
    if conv.status = 'RESPONDIDO' then return json_build_object('ok', false, 'msg', 'Este link já foi utilizado.'); end if;
    if v_email !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' then
      return json_build_object('ok', false, 'msg', 'Informe um e-mail válido.');
    end if;
    v_empresa := null;

  else
    return json_build_object('ok', false, 'msg', 'Link inválido.');
  end if;

  insert into public.respostas (tipo, token, nome, email, empresa, disponibilidade, tamanho)
  values (v_tipo, v_token, v_nome, nullif(v_email, ''), v_empresa, v_disp, case when v_disp = 'Sim' then v_tam else '-' end);

  if conv.id is not null then
    update public.convidados
       set status = 'RESPONDIDO', respondido_em = now(),
           nome  = coalesce(nullif(convidados.nome, ''), v_nome),
           email = coalesce(nullif(convidados.email, ''), nullif(v_email, ''))
     where id = conv.id;
  end if;

  return json_build_object('ok', true, 'presenca', v_disp = 'Sim');
end $$;

-- Só as duas funções ficam liberadas para o site
revoke all on function public.obter_contexto(text, text) from public;
revoke all on function public.enviar_resposta(json)       from public;
revoke all on function public.norm(text)                  from public, anon, authenticated;
grant execute on function public.obter_contexto(text, text) to anon, authenticated;
grant execute on function public.enviar_resposta(json)       to anon, authenticated;

-- ---------- Visões para acompanhar (abra no Table Editor / SQL Editor) ----------
create or replace view public.resumo_abadas with (security_invoker = true) as
  select tamanho, count(*) as quantidade
    from public.respostas where disponibilidade = 'Sim'
   group by tamanho order by array_position(array['M/G','GG/XG'], tamanho);

create or replace view public.resumo_geral with (security_invoker = true) as
  select tipo,
         count(*) filter (where disponibilidade = 'Sim') as vao,
         count(*) filter (where disponibilidade = 'Não') as nao_vao,
         count(*) as total
    from public.respostas group by tipo;

create or replace view public.pendentes with (security_invoker = true) as
  select tipo, numero, nome, email, empresa, token
    from public.convidados where status = 'PENDENTE' order by tipo, numero, nome;