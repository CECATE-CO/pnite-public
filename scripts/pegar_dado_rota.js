/**
 * PNITE — Exemplo de consulta autenticada à API REST do Supabase (JavaScript / Node.js 20.12+).
 *
 * Fluxo:
 * 1. Autentica o usuário (USER_ID / USER_PASSWORD) no Supabase Auth usando a
 *    chave publicável (SUPABASE_PUBLISHABLE_KEY) e obtém um access_token (JWT);
 * 2. Consulta a tabela dado_bruto_rotas pelo PostgREST (/rest/v1) enviando o
 *    token no cabeçalho Authorization. As tabelas dado_bruto_* têm RLS ativo e só
 *    liberam SELECT ao papel "authenticated".
 *
 * Sem dependências (fetch nativo). No navegador, o mesmo código funciona
 * substituindo a leitura do .env por configuração da página — nunca exponha a
 * SUPABASE_SECRET_KEY no front-end.
 *
 * Uso:
 *   node scripts/pegar_dado_rota.js [UF] [LIMITE]
 *   node scripts/pegar_dado_rota.js GO 5
 */

const path = require("node:path");

process.loadEnvFile(path.join(__dirname, "..", ".env"));

const PROJECT_URL = process.env.PROJECT_URL.replace(/\/$/, "");
const CHAVE_PUBLICAVEL = process.env.SUPABASE_PUBLISHABLE_KEY;

async function verificar(resp) {
  if (!resp.ok) throw new Error(`HTTP ${resp.status}: ${await resp.text()}`);
  return resp;
}

/** Login por e-mail/senha no Supabase Auth; retorna o access_token (JWT). */
async function autenticar(email, senha) {
  const resp = await fetch(`${PROJECT_URL}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: CHAVE_PUBLICAVEL, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password: senha }),
  }).then(verificar);
  return (await resp.json()).access_token;
}

/** Busca rotas (sem a coluna shape, que pode ter vários MB por linha). */
async function pegarRotas(token, { uf = null, limite = 10, offset = 0 } = {}) {
  const params = new URLSearchParams({
    select: "ano_carga,codigo_cidade,nome_cidade,uf,id_rota,nome,km,tempo,tipo,ativo",
    order: "codigo_cidade.asc,id_rota.asc",
    limit: String(limite),
    offset: String(offset),
  });
  if (uf) params.set("uf", `eq.${uf.toUpperCase()}`); // filtros PostgREST: eq, gt, lt, in.(...), ilike etc.

  const resp = await fetch(`${PROJECT_URL}/rest/v1/dado_bruto_rotas?${params}`, {
    headers: {
      apikey: CHAVE_PUBLICAVEL,
      Authorization: `Bearer ${token}`,
      Prefer: "count=exact", // total de registros retornado em Content-Range
    },
  }).then(verificar);
  const total = (resp.headers.get("content-range") || "*/?").split("/").pop();
  return { rotas: await resp.json(), total };
}

/** Busca o GeoJSON (shape) de uma rota específica (chave: codigo_cidade + id_rota). */
async function pegarShape(token, codigoCidade, idRota) {
  const params = new URLSearchParams({
    select: "shape",
    codigo_cidade: `eq.${codigoCidade}`,
    id_rota: `eq.${idRota}`,
  });
  const resp = await fetch(`${PROJECT_URL}/rest/v1/dado_bruto_rotas?${params}`, {
    headers: { apikey: CHAVE_PUBLICAVEL, Authorization: `Bearer ${token}` },
  }).then(verificar);
  const dados = await resp.json();
  return dados.length ? dados[0].shape : null;
}

async function main() {
  const uf = process.argv[2] || null;
  const limite = Number(process.argv[3] || 10);

  const token = await autenticar(process.env.USER_ID, process.env.USER_PASSWORD);
  const { rotas, total } = await pegarRotas(token, { uf, limite });
  console.log(`Total de rotas${uf ? ` em ${uf.toUpperCase()}` : ""}: ${total} — exibindo ${rotas.length}`);
  for (const r of rotas) {
    console.log(`  ${r.uf} | ${r.nome_cidade.padEnd(28)} | rota ${String(r.id_rota).padStart(6)} | ${String(r.km).padStart(8)} km | ${r.nome}`);
  }

  if (rotas.length) {
    const shape = await pegarShape(token, rotas[0].codigo_cidade, rotas[0].id_rota);
    console.log(shape ? `Shape da 1ª rota: ${shape.length.toLocaleString("pt-BR")} caracteres` : "1ª rota sem shape cadastrado");
  }
}

main().catch((erro) => {
  console.error(erro.message);
  process.exit(1);
});
