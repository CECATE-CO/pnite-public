# Modelos de e-mail — PNITE / CECATE Centro-Oeste

Modelos HTML dos e-mails do Supabase Auth (GoTrue), no padrão visual do CECATE (âmbar `#F5A800` e grafite `#3f3f46`).
São publicados pela Vercel em `https://pnite.vercel.app/email/` (ver `scripts/build_vercel.mjs`), e o servidor do Supabase os baixa por URL.

| Arquivo | E-mail | Assunto sugerido |
|---|---|---|
| `recuperacao.html` | Redefinição de senha (`recovery`) | PNITE — Redefinição de senha |
| `confirmacao.html` | Confirmação de cadastro (`confirmation`); também é o e-mail do botão "Por convite" / "Reenviar convite" da Gestão de Usuários, cujo link abre `redefinir-senha.html` | PNITE — Confirme seu cadastro |
| `convite.html` | Convite (`invite`) | PNITE — Convite de acesso |
| `logo_cecate.png` | Logo (PNG extraído de `assets/logos/logo_cecate.svg`; clientes de e-mail não exibem SVG) | — |

Variáveis usadas: `{{ .ConfirmationURL }}` (link do botão) e `{{ .Email }}` (rodapé).

## Ativação no servidor (Supabase auto-hospedado)

1. No `.env` do servidor (pasta do docker compose do Supabase), acrescentar as variáveis `GOTRUE_MAILER_TEMPLATES_*` e `GOTRUE_MAILER_SUBJECTS_*` do `.env.example`.
2. No `docker-compose.yml`, em `services: auth: environment:`, repassar cada uma:
   ```yaml
   GOTRUE_MAILER_TEMPLATES_RECOVERY: ${GOTRUE_MAILER_TEMPLATES_RECOVERY}
   GOTRUE_MAILER_SUBJECTS_RECOVERY: ${GOTRUE_MAILER_SUBJECTS_RECOVERY}
   GOTRUE_MAILER_TEMPLATES_CONFIRMATION: ${GOTRUE_MAILER_TEMPLATES_CONFIRMATION}
   GOTRUE_MAILER_SUBJECTS_CONFIRMATION: ${GOTRUE_MAILER_SUBJECTS_CONFIRMATION}
   GOTRUE_MAILER_TEMPLATES_INVITE: ${GOTRUE_MAILER_TEMPLATES_INVITE}
   GOTRUE_MAILER_SUBJECTS_INVITE: ${GOTRUE_MAILER_SUBJECTS_INVITE}
   GOTRUE_SMTP_MAX_FREQUENCY: ${GOTRUE_SMTP_MAX_FREQUENCY}   # intervalo entre e-mails (10s; a PNITE mostra a contagem)
   ```
3. Aplicar com `docker compose up -d auth` (não usar `restart`, que não relê o `.env`).

Os modelos só são lidos depois que a Vercel publicar a versão com a pasta `email/`.
