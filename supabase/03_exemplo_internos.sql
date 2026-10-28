-- Modelo para cadastrar os colaboradores INTERNOS.
-- Troque pelos dados reais (ou importe um CSV pelo Table Editor > convidados > Insert > Import CSV,
-- com as colunas: tipo, nome, email, empresa — tipo = INTERNO).
insert into public.convidados (tipo, nome, email, empresa) values
  ('INTERNO', 'Maria da Silva Souza', 'maria.souza@oros.com.br', 'OROS'),
  ('INTERNO', 'João Pereira Lima',    'joao.lima@vobys.com.br',  'VOBYS');

-- Opcional: lista de nomes autorizados da SEDUC (se ficar vazia, qualquer nome completo é aceito)
-- insert into public.lista_seduc (nome) values ('Ana Paula Ferreira'), ('Carlos Eduardo Rocha');
