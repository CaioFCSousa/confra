# Confraternização 2026 — Supabase + Vercel + Cloudflare

Mesma lógica do Apps Script, agora com banco no **Supabase** e site na **Vercel**.

| Link | Quem usa | O que valida |
|---|---|---|
| `festa.orossolucoes.com.br/interno` (ou `/?f=interno`) | Colaboradores | Nome + e-mail corporativo iguais ao cadastro em `convidados` |
| `festa.orossolucoes.com.br/seduc` (ou `/?f=seduc`) | SEDUC | Só nome completo; sem repetir nome (e só da `lista_seduc`, se preenchida) |
| `festa.orossolucoes.com.br/?t=TOKEN` (ou `/c/TOKEN`) | 30 externos | Token único, vale uma resposta só — **os QR codes já gerados continuam valendo** |

```
confra-vercel/
├─ public/            -> o site (vai para a Vercel)
│  ├─ index.html      -> formulário (mesmo visual)
│  ├─ config.js       -> URL e chave do Supabase (único arquivo que você edita)
│  └─ assets/         -> imagens
├─ supabase/
│  ├─ 01_schema.sql              -> tabelas, regras e funções
│  ├─ 02_convidados_externos.sql -> os 30 tokens (mesmos números dos QR codes)
│  └─ 03_exemplo_internos.sql    -> modelo para cadastrar os internos
└─ vercel.json        -> rotas (/interno, /seduc, /c/TOKEN)
```

---

## 1. Supabase (banco)

1. Crie um projeto em supabase.com (região **South America – São Paulo**).
2. Vá em **SQL Editor → New query**, cole o conteúdo de `01_schema.sql` e clique **Run**.
3. Faça o mesmo com `02_convidados_externos.sql` (os 30 tokens).
4. Cadastre os **internos**: edite e rode `03_exemplo_internos.sql`, **ou** vá em
   **Table Editor → convidados → Insert → Import data from CSV** com as colunas
   `tipo,nome,email,empresa` (tipo = `INTERNO`).
5. Ajuste prazo, domínios e empresas em **Table Editor → config** (uma linha só):
   - `prazo` → data/hora limite (depois dela o formulário fecha sozinho)
   - `dominios` → ex.: `{orossolucoes.com.br,vobys.com.br}`; deixe `{}` para aceitar qualquer domínio
6. Em **Project Settings → API**, copie **Project URL** e a chave **anon public**.

> A chave *anon* pode ficar no site: as tabelas estão fechadas (RLS) e ela só consegue
> chamar as duas funções do formulário. **Nunca** coloque a chave *service_role* no site.

## 2. Vercel (site)

1. Edite `public/config.js` com a URL e a chave anon.
2. Suba a pasta `confra-vercel` para um repositório no GitHub.
3. Em vercel.com → **Add New → Project** → importe o repositório.
   - Framework Preset: **Other** · sem build command · o `vercel.json` já aponta para `public/`.
4. **Deploy**. Teste no endereço `*.vercel.app` que a Vercel mostrar:
   `/interno`, `/seduc` e `/c/7fced5a5ff3363463178`.

*(Sem GitHub: `npm i -g vercel` e rode `vercel --prod` dentro da pasta.)*

## 3. Cloudflare (domínio)

1. Na Vercel: **Project → Settings → Domains → Add** → `festa.orossolucoes.com.br`.
2. No Cloudflare: **DNS → Add record**
   - Type: `CNAME` · Name: `festa` · Target: `cname.vercel-dns.com`
   - Proxy status: **DNS only (nuvem cinza)** ← importante, a Vercel cuida do HTTPS.
3. **Apague** as Redirect Rules ou o Worker que criamos antes para o `festa`, se existirem.
4. Em alguns minutos a Vercel mostra o domínio como **Valid** e o certificado é emitido.

Pronto: `festa.orossolucoes.com.br` abre direto o formulário, sem redirecionamento e sem faixa do Google.

---

## Acompanhando as respostas

No Supabase, **Table Editor** (ou SQL Editor):

| Onde | O que mostra |
|---|---|
| `respostas` | todas as respostas (botão **Export → CSV** para planilha) |
| `resumo_abadas` | quantos abadás de cada tamanho |
| `resumo_geral` | quem vai / não vai, por tipo de convidado |
| `pendentes` | quem ainda não respondeu (com o nº do QR dos externos) |
| `convidados` | status de cada interno/externo |

Para liberar alguém responder de novo (ex.: errou o tamanho):
```sql
delete from respostas where email = 'fulano@oros.com.br';
update convidados set status = 'PENDENTE', respondido_em = null where email = 'fulano@oros.com.br';
```
