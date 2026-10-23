/**
 * PNITE — Monta o site estático publicado na Vercel em dist/.
 *
 * Só os arquivos de PUBLICAVEIS vão para dist/ (lista fechada): os dados vêm das APIs do
 * Supabase e do IBGE; dados brutos locais (data/, upload/) nunca podem ser servidos.
 *
 * config.local.js é gerado com os mesmos valores públicos de scripts/gerar_config_web.py
 * (URL do Supabase, chave publishable e ano de carga), lidos das variáveis de ambiente da
 * Vercel ou, localmente, do .env. A chave secreta nunca é lida.
 *
 * Uso: node scripts/build_vercel.mjs   (a Vercel executa via vercel.json)
 */

import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..');
const DIST = join(RAIZ, 'dist');

// [origem no repositório, destino em dist/]
const PUBLICAVEIS = [
  ['PNITE.html', 'index.html'],
  ['assets/logos', 'assets/logos'],
  ['assets/img', 'assets/img'],
];

const PERMITIDAS = { SUPABASE_URL: 'supabaseUrl', SUPABASE_PUBLISHABLE_KEY: 'publishableKey', ANO_CARGA_SETE: 'anoCarga' };

function falhar(msg) {
  console.error(`build_vercel: ${msg}`);
  process.exit(1);
}

/** Variáveis públicas: ambiente (Vercel) primeiro; .env local como reserva. */
function lerConfig() {
  const local = {};
  const arqEnv = join(RAIZ, '.env');
  if (existsSync(arqEnv)) {
    for (const linha of readFileSync(arqEnv, 'utf8').split(/\r?\n/)) {
      const m = linha.match(/^\s*([A-Z_]+)\s*=\s*(.*?)\s*$/);
      if (m && m[1] in PERMITIDAS) local[m[1]] = m[2].replace(/^(['"])(.*)\1$/, '$2');
    }
  }
  const valores = Object.fromEntries(Object.keys(PERMITIDAS).map(v => [v, process.env[v] || local[v]]));
  const faltando = Object.keys(valores).filter(v => !valores[v]);
  if (faltando.length) falhar(`variáveis ausentes: ${faltando.join(', ')} (configure em Settings → Environment Variables na Vercel)`);
  if (!valores.SUPABASE_PUBLISHABLE_KEY.startsWith('sb_publishable_')) falhar('SUPABASE_PUBLISHABLE_KEY não parece uma chave publishable; nada foi gerado.');
  const ano = Number.parseInt(valores.ANO_CARGA_SETE, 10);
  if (Number.isNaN(ano)) falhar('ANO_CARGA_SETE não é um ano válido.');
  return { supabaseUrl: valores.SUPABASE_URL.replace(/\/+$/, ''), publishableKey: valores.SUPABASE_PUBLISHABLE_KEY, anoCarga: ano };
}

const config = lerConfig();
rmSync(DIST, { recursive: true, force: true });
for (const [origem, destino] of PUBLICAVEIS) {
  const de = join(RAIZ, origem);
  if (!existsSync(de)) falhar(`arquivo publicável ausente: ${origem}`);
  mkdirSync(dirname(join(DIST, destino)), { recursive: true });
  cpSync(de, join(DIST, destino), { recursive: true });
}
writeFileSync(join(DIST, 'config.local.js'),
  '// Gerado por scripts/build_vercel.mjs — contém apenas valores públicos (URL e chave publishable).\n'
  + `window.PNITE_CONFIG = ${JSON.stringify(config, null, 2)};\n`, 'utf8');

const versao = readFileSync(join(RAIZ, 'PNITE.html'), 'utf8').match(/const PNITE_VERSION = "([^"]+)"/);
console.log(`build_vercel: dist/ pronto (${versao ? versao[1] : 'versão não encontrada'}; ${PUBLICAVEIS.length} itens + config.local.js)`);
