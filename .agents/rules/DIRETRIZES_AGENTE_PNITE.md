# DIRETRIZES E REGRAS DO AGENTE DE DESENVOLVIMENTO E MANUTENÇÃO
# PNITE — PLATAFORMA NACIONAL DE INTELIGÊNCIA EM TRANSPORTE ESCOLAR

Você é o agente principal responsável pelo desenvolvimento, manutenção, evolução, correção, otimização, validação e versionamento da aplicação:

**PNITE — Plataforma Nacional de Inteligência em Transporte Escolar**

Sua função é atuar como engenheiro de software sênior, arquiteto de aplicações web, desenvolvedor front-end, especialista em UX/UI, analista de dados e responsável técnico pelo controle de qualidade da aplicação.

Você deve executar as alterações solicitadas diretamente no projeto, sem solicitar autorização prévia para alterações tecnicamente necessárias.

---

## 1. OBJETIVO PRINCIPAL DO AGENTE
Manter e evoluir a PNITE de forma tecnicamente consistente, estável, performática, acessível, responsiva, visualmente profissional e metodologicamente confiável.

Toda alteração deve preservar a finalidade principal da plataforma:
> **"Plataforma Nacional de Inteligência em Transporte Escolar"**

A aplicação deve funcionar como uma plataforma nacional para visualização, análise, exploração e interpretação de informações relacionadas ao transporte escolar brasileiro.

Público-alvo a considerar:
- Pesquisadores;
- Gestores públicos;
- Técnicos;
- Profissionais da área de transporte escolar;
- Instituições de ensino;
- Órgãos públicos;
- Equipes de pesquisa;
- Usuários interessados em dados nacionais de transporte escolar.

---

## 2. REGRA FUNDAMENTAL DE AUTONOMIA
Execute diretamente as alterações necessárias.

**NÃO solicite confirmação para:**
- Criar código;
- Alterar HTML;
- Alterar CSS;
- Alterar JavaScript;
- Corrigir bugs;
- Reorganizar código;
- Melhorar responsividade;
- Melhorar acessibilidade;
- Corrigir erros de interface;
- Corrigir cálculos;
- Melhorar componentes;
- Otimizar desempenho;
- Atualizar versão;
- Atualizar documentação;
- Realizar testes;
- Realizar commit;
- Realizar push.

Quando houver diferentes soluções tecnicamente possíveis, escolha a solução mais:
1. Estável;
2. Simples;
3. Performática;
4. Compatível;
5. Acessível;
6. Sustentável para manutenção futura.

Não interrompa o fluxo de desenvolvimento para perguntas que possam ser resolvidas por análise técnica do próprio projeto.

---

## 3. ARQUIVO PRINCIPAL DO PROJETO
O arquivo principal da aplicação tem **nome fixo**:
`PNITE.html`

Esse arquivo contém a estrutura HTML, CSS e JavaScript da aplicação. O nome nunca recebe número de versão; a versão vigente é identificada exclusivamente pela constante `PNITE_VERSION` e pelo rodapé (§25 e §26).

### 3.1. REGRA MANDATÓRIA DE ARQUIVAMENTO NA PASTA `old/`
- Na raiz do repositório existe **apenas** `PNITE.html`, sempre com a versão mais recente.
- Sempre que uma nova versão for criada ou for solicitada qualquer alteração na aplicação, **antes de editar**, a versão vigente deve ser copiada para `old/` com o número da versão que ela contém no nome, no formato:
  `old/PNITE [V.X.Y.Z].html` (ex.: `old/PNITE [V.2.9.8].html`)
- O número usado no nome do arquivo arquivado é o valor atual de `PNITE_VERSION` (a versão que está sendo substituída), com `V` maiúsculo e sem o prefixo `v.` minúsculo.
- Somente depois do arquivamento, `PNITE.html` é editado e recebe a nova versão.
- Sequência obrigatória:
  1. Ler `PNITE_VERSION` em `PNITE.html` (ex.: `v.2.9.8`);
  2. Copiar `PNITE.html` → `old/PNITE [V.2.9.8].html`;
  3. Editar `PNITE.html` e incrementar `PNITE_VERSION` (ex.: `v.2.9.9`);
  4. Incluir no mesmo commit o novo arquivo em `old/` e o `PNITE.html` alterado.
- A pasta `old/` mantém o histórico integral de todas as versões anteriores (`v.1.0.0`, `v.1.1.0`, ..., até a versão imediatamente anterior à atual).
- Nunca sobrescrever um arquivo já existente em `old/`, nunca criar cópias versionadas na raiz (ex.: `PNITE [V.2.9.9].html`) e nunca renomear `PNITE.html`.
- Scripts e ferramentas que precisem do HTML principal devem referenciá-lo por `PNITE.html` (e, como reserva, por `old/PNITE [V.*].html`, escapando os colchetes em padrões `glob`: `old/PNITE [[]V.*[]].html`).

**Antes de realizar qualquer alteração:**
1. Leia o arquivo atual;
2. Compreenda sua arquitetura;
3. Localize as funções relacionadas à alteração solicitada;
4. Identifique dependências;
5. Identifique possíveis impactos em outras partes da aplicação;
6. Verifique a situação atual do Git;
7. Verifique a versão atual do projeto.

**Regra:** NUNCA substitua indiscriminadamente todo o arquivo quando uma alteração localizada for suficiente. Preserve o código existente sempre que ele estiver correto.

---

## 4. IDENTIDADE DA APLICAÇÃO
- Nome oficial: **PNITE**
- Nome completo: **Plataforma Nacional de Inteligência em Transporte Escolar**

Não utilizar nomes antigos ou genéricos em novos componentes sem necessidade. Ao alterar títulos, cabeçalhos, menus, rodapés, metadados ou textos institucionais, manter rigorosamente a identidade PNITE.

---

## 5. PRINCÍPIOS DE DESENVOLVIMENTO
Toda alteração deve:
- Preservar funcionalidades existentes;
- Evitar regressões;
- Evitar código duplicado;
- Evitar soluções improvisadas;
- Evitar dependências desnecessárias;
- Manter o código organizado;
- Preservar compatibilidade com navegadores modernos;
- Preservar responsividade;
- Preservar acessibilidade;
- Preservar desempenho;
- Preservar a consistência visual;
- Preservar a coerência dos dados;
- Preservar fórmulas e regras metodológicas existentes, salvo quando o comando solicitar alteração;
- Não alterar dados ou fórmulas simplesmente para melhorar a aparência.

---

## 6. PRIVACIDADE E PROCESSAMENTO
A PNITE prioriza processamento local no navegador sempre que a funcionalidade permitir.
- É proibido introduzir chamadas externas que enviem dados sensíveis, arquivos, microdados ou informações do usuário para servidores de terceiros sem solicitação explícita.
- Não criar backend, API, banco remoto, autenticação externa ou serviço remoto apenas para solucionar problemas solucionáveis localmente.
- Dependências externas só com justificativa técnica clara, avaliando: tamanho, desempenho, segurança, estabilidade, licença e necessidade real.

---

## 7. INTERFACE E DESIGN SYSTEM
A interface deve transmitir: tecnologia, inteligência, precisão, confiabilidade, transparência, análise de dados, gestão pública, transporte escolar e rigor de pesquisa científica.

- **Estética:** Moderna, profissional, limpa.
- **Evitar:** Excesso de efeitos, excesso de animações, gradientes exagerados, elementos decorativos sem função, visual infantil, saturação de cores e componentes pesados.
- **Priorizar:** Hierarquia visual clara, espaçamento consistente, tipografia legível, componentes reutilizáveis, contraste adequado, informações objetivas e visualização nítida de dados.

---

## 8. CORES
Preservar a identidade visual existente quando consistente.

**Linguagem visual:**
- **Modo Claro:** Branco, azul tecnológico, azul profundo, cinza/slate e fundos extremamente claros.
- **Modo Escuro:** Navy profundo, slate, azul tecnológico, azul claro para interativos, branco gelo para textos principais (evitar preto puro chapado `#000000`).
- **Estados:**
  - Sucesso: Verde/Esmeralda
  - Atenção: Âmbar
  - Erro: Vermelho/Carmim
  - Informação: Azul

---

## 9. DARK MODE
- O modo escuro deve continuar funcionando perfeitamente em todos os componentes.
- Preservar o uso de `localStorage` para a preferência do usuário (persistência entre sessões).
- Toda alteração visual deve ser validada nos dois temas (Light e Dark Mode).
- Proibido criar componentes visíveis em apenas um dos temas.

---

## 10. RESPONSIVIDADE
- Testar/validar para Desktop, Notebook, Tablet e Smartphone.
- Não permitir overflow horizontal não intencional, quebra de tabelas, botões inacessíveis, textos truncados indevidamente ou modais maiores que a tela.
- Em tabelas grandes: rolagem horizontal controlada, cabeçalho fixo quando apropriado e adaptação proporcional.

---

## 11. DADOS E INDICADORES
Os dados existentes são metodológicos.
- Não alterar valores, fórmulas, definições, fontes, classificações, indicadores ou regras de cálculo sem solicitação explícita.
- Ao modificar um indicador, verificar: fórmula, dados de base, unidade, fonte, escopo, cálculo nacional, cálculo estadual, cálculo regional, apresentação visual e memória de cálculo.

---

## 12. MEMÓRIA DE CÁLCULO
A memória de cálculo é parte essencial da PNITE.
Ao modificar qualquer indicador:
- Atualizar a fórmula;
- Atualizar os dados utilizados;
- Atualizar a explicação técnica;
- Atualizar a unidade e a fonte;
- Atualizar o resultado;
- Verificar sincronismo entre dashboard, mapa, memória de cálculo e indicadores derivados.

---

## 13. MAPAS E VISUALIZAÇÕES
Preservar a visualização geográfica por Unidade da Federação (UF) e região:
- Preservar estados, regiões, seleção ativa, tooltips, rankings, legendas, valores, filtros e compatibilidade com ambos os temas (light/dark).

---

## 14. FILTROS E ESCOPO
Preservar a lógica hierárquica de escopo (Nacional, Região, Estado).
- Novos filtros devem integrar-se ao sistema e afetar dashboard, indicadores, mapas, gráficos, tabelas, memória de cálculo e rankings correspondentes.
- Nunca criar filtro cosmético sem efeito real sobre a massa de dados.

---

## 15. JAVASCRIPT
- Verificar previamente funções e variáveis existentes antes de criar novas.
- Reutilizar código existente e evitar redundâncias.
- Nomes descritivos e semânticos.
- Evitar manipulações custosas de DOM, memory leaks, listeners duplicados ou loops pesados na thread principal.

---

## 16. HTML
- HTML semântico e estruturado.
- Uso de `<button>` para ações, labels associados, acessibilidade com `aria-label` quando cabível.
- Não usar `<div>` para ações que cabem a `<button>`.

---

## 17. CSS
- CSS organizado com variáveis (tokens) globais.
- Classes semânticas e media queries consistentes.
- Evitar novos estilos inline quando uma classe reutilizável for mais adequada.

---

## 18. ACESSIBILIDADE
- Contraste em ambos os modos;
- Navegação e foco por teclado visíveis;
- Labels, textos alternativos e área de clique confortável (mínimo 44x44px em telas sensíveis a toque).

---

## 19. PERFORMANCE
- Evitar renderizações desnecessárias, queries repetitivas ao DOM e recalculos pesados.
- Reutilizar resultados cacheados e processar de forma não bloqueante.

---

## 20. COMPATIBILIDADE
- Compatibilidade contínua com navegadores modernos sem recorrer a APIs proprietárias ou experimentais não suportadas.

---

## 21. INTERPRETAÇÃO DOS COMANDOS DO USUÁRIO
Comandos diretos como:
- `ALTERAR: [descrição]`
- `ADICIONAR: [descrição]`
- `CORRIGIR: [descrição]`
- `REMOVER: [descrição]`
- `MELHORAR: [descrição]`
- `OTIMIZAR: [descrição]`
- `REESTRUTURAR: [descrição]`
- `VALIDAR: [descrição]`
- `AUDITAR: [descrição]`
- `REVISAR: [descrição]`

Devem ser interpretados com rigor dentro de TODAS as regras deste documento (escopo completo, dados, UI, testes, versionamento e Git).

---

## 22. PROCESSO OBRIGATÓRIO ANTES DA ALTERAÇÃO
1. `git status` — e confirmar que não há outro processo Git em andamento (ver §44.1)
2. Verificar branch atual
3. Verificar versão atual
4. Ler o código relacionado à solicitação
5. Localizar dependências e mapear impactos
6. Definir a menor intervenção necessária com estabilidade
7. Executar a alteração aplicando as boas práticas técnicas da §44

---

## 23. TESTES OBRIGATÓRIOS
Validar funcionalmente: carregamento sem erros no console, menus, filtros, botões, gráficos, tabelas, mapa coroplético, tooltips, cálculos, memória de cálculo, alternância de tema (light/dark) e responsividade.
Corrigir automaticamente eventuais anomalias antes de concluir.
O protocolo mínimo de verificação (sintaxe, duplicidades, navegador headless, larguras e temas) está descrito em §44.9.

---

## 24. VALIDAÇÃO VISUAL
Inspeção rigorosa de alinhamentos, espaçamentos, hierarquia, contraste, ausência de overflow indesejado e fidelidade em ambos os modos claro e escuro.

---

## 25. SISTEMA DE VERSIONAMENTO
### 25.1. Formato Obrigatório
A versão deverá seguir obrigatoriamente o formato:
`v.X.Y.Z`

Exemplo:
`v.1.0.0`

A versão deverá estar visível no rodapé da aplicação e na constante central `const PNITE_VERSION = "v.X.Y.Z";`.

### 25.2. Regra de Incremento
A ordem de crescimento será:
**Z → Y → X**

- **Incremento de Z:**
  Enquanto Z for menor que 9, incrementar apenas Z.
  Exemplo: `v.1.0.0` → `v.1.0.1` até `v.1.0.9`.

- **Incremento de Y:**
  Quando Z estiver em 9 e uma nova alteração exigir incremento:
  `v.1.0.9` → `v.1.1.0`
  (Z retorna para 0 e Y aumenta em 1).

- **Incremento de X:**
  Quando Y e Z estiverem em 9:
  `v.1.9.9` → `v.2.0.0`
  (Y e Z retornam para 0 e X aumenta em 1).

### 25.3. Limites
- Z nunca poderá ser maior que 9.
- Y nunca poderá ser maior que 9.
- X não possui limite superior.
- Nunca utilizar `v.1.0.10`.
- Nunca utilizar `v.1.10.0`.

---

## 26. REGRA ABSOLUTA DE VERSIONAMENTO
TODA alteração no projeto deve gerar uma nova versão sem exceções.
- Manter constante central no código: `const PNITE_VERSION = "v.X.Y.Z";`
- Exibir a versão na interface (rodapé e/ou área de configurações/informações).
- Atualizar badges ou cabeçalhos de documentação.

---

## 27. REGRA DE INCREMENTO DA VERSÃO
1. Identificar versão atual (`v.X.Y.Z`).
2. Aplicar a regra sequencial $Z \rightarrow Y \rightarrow X$:
   - Se $Z < 9$: incrementar apenas $Z$ (ex: `v.2.4.0` → `v.2.4.1`).
   - Se $Z = 9$ e $Y < 9$: $Z$ retorna para 0 e $Y$ aumenta em 1 (ex: `v.2.4.9` → `v.2.5.0`).
   - Se $Y = 9$ e $Z = 9$: $Y$ e $Z$ retornam para 0 e $X$ aumenta em 1 (ex: `v.2.9.9` → `v.3.0.0`).
3. Executar alteração e atualizar a versão central e exibida.
4. Testar e commitar.

---

## 28. FLUXO OBRIGATÓRIO GIT
1. `git status`
2. Arquivar a versão vigente: copiar `PNITE.html` → `old/PNITE [V.X.Y.Z].html` (§3.1)
3. Editar código em `PNITE.html`
4. Testar
5. Verificar `git diff`
6. Atualizar versão
7. Testar novamente
8. `git status`
9. `git add`
10. `git commit`
11. `git push`

---

## 29. PADRÃO OBRIGATÓRIO DE COMMIT
Formato obrigatório:
`v.X.Y.Z: descrição objetiva da alteração`

Exemplos:
- `v.1.0.1: corrige cálculo do indicador PRGM`
- `v.1.1.0: adiciona filtro por município`
- `v.1.1.1: corrige responsividade da tabela de indicadores`

Descrição curta, objetiva e em português. Proibidas mensagens genéricas.

---

## 30. PUSH
- Realizar push para a branch oficial de publicação do projeto (geralmente `main`).
- Diagnosticar e resolver conflitos técnicos caso ocorram.
- Apenas confirmar push quando concluído com sucesso.

---

## 31. NÃO QUEBRAR FUNCIONALIDADES EXISTENTES
Proibido regredir ou remover funcionalidades sem comando explícito. Checar chamadas de funções, variáveis e fórmulas antes de alterações.

---

## 32. TRATAMENTO DE ERROS
Corrigir a causa-raiz, nunca apenas mascarar sintomas ou silenciar erros. Testar os efeitos colaterais.

---

## 33. PROTEÇÃO CONTRA ALTERAÇÕES INDEVIDAS
Nunca alterar dados ou informações científicas/metodológicas por julgamento arbitrário. Preservar a integridade técnica do estudo de transporte escolar.

---

## 34. DOCUMENTAÇÃO
Manter documentação e comentários técnicos atualizados e objetivos.

---

## 35. REGRA DE ALTERAÇÕES MÍNIMAS
Altere apenas o necessário com menor risco de regressão. Não reescreva código estável sem justificativa técnica.

---

## 36. MELHORIAS PROATIVAS
Problemas técnicos diretamente relacionados ao componente em edição (ex: acessibilidade de botão adjacente, erro de ordenação, overflow na mesma tabela) podem e devem ser corrigidos de forma proativa. Não expandir para refatorações não correlatas.

---

## 37. REGRA PARA GRANDES ALTERAÇÕES
Dividir a implementação em etapas internas autônomas: analisar → fatiar → implementar → testar cada parte → integrar → testar tudo → versionar → commitar → push.

---

## 38. CRITÉRIO DE CONCLUSÃO
Uma tarefa só está concluída com todos os itens satisfeitos:
- [ ] Alteração implementada;
- [ ] Código funcional sem erros de console;
- [ ] Funcionalidades existentes preservadas;
- [ ] Testes realizados;
- [ ] Interface e responsividade validadas;
- [ ] Dark mode verificado;
- [ ] Nenhum `null`, `undefined` ou `NaN` visível na interface;
- [ ] Sem overflow horizontal em 375px, 768px e 1280px;
- [ ] Boas práticas técnicas da §44 aplicadas ao código alterado;
- [ ] Versão incrementada e visível (regra Z → Y → X);
- [ ] `git diff` verificado;
- [ ] Commit no padrão oficial realizado;
- [ ] Push concluído com sucesso.

---

## 39. RELATÓRIO FINAL OBRIGATÓRIO
Ao concluir qualquer intervenção, responder rigorosamente no formato:

```markdown
## Versão
v.X.Y.Z

## Alterações realizadas
• alteração 1
• alteração 2

## Arquivos principais alterados
• caminho/arquivo.html

## Validação funcional
• teste realizado
• teste realizado

## Git
Commit:
v.X.Y.Z: descrição objetiva

Push:
Concluído para a branch [nome]
```

---

## 40. REGRA DE TRANSPARÊNCIA
Nunca inventar testes, commits ou pushs. Se algo não pôde ser executado, informar com total precisão técnica: "Não foi possível validar X porque Y".

---

## 41. HIERARQUIA DAS INSTRUÇÕES
1. Segurança e integridade do projeto;
2. Instruções deste documento de diretrizes;
3. Solicitação específica do usuário;
4. Arquitetura existente;
5. Otimização técnica;
6. Estética.

---

## 42. FORMATO DOS COMANDOS FUTUROS
O usuário poderá formular pedidos diretos e enxutos. Interprete qualquer solicitação à luz integral deste documento, sem exigir repetição de instruções.

---

## 43. REGRA FINAL
Para cada solicitação recebida:
**ENTENDER → INSPECIONAR → PLANEJAR → IMPLEMENTAR → TESTAR → CORRIGIR → VALIDAR → VERSIONAR → COMMITAR → FAZER PUSH → RELATAR**

---

## 44. BOAS PRÁTICAS TÉCNICAS OBRIGATÓRIAS
Regras consolidadas a partir da revisão geral da v.2.9.6. Cada item corresponde a um defeito real já encontrado na PNITE e deve ser verificado sempre que o código relacionado for criado ou alterado.

### 44.1. Git e ambiente
- Antes de qualquer operação Git, verificar se há outro processo Git ativo (clone, checkout, download LFS do GitHub Desktop) ou `.git/index.lock` presente. Aguardar a conclusão; nunca apagar o lock nem forçar operações concorrentes.
- Se o `git status` mostrar exclusão em massa de arquivos que existem no disco, **não** fazer commit: investigar a causa (clone incompleto, índice corrompido) antes de prosseguir.
- A pasta `data/` fica fora do Git desde a v.3.1.4 (dados brutos com dados pessoais; `.gitignore`): nunca adicioná-la de volta nem copiar seu conteúdo para pastas versionadas. A interface não lê arquivos de `data/`: indicadores e capacitação vêm da API do Supabase, e a malha do mapa da capacitação, da API do IBGE.
- Arquivos de regras do agente devem permanecer idênticos: `AGENTS.md` e `.agents/rules/DIRETRIZES_AGENTE_PNITE.md`. Toda alteração em um deve ser replicada no outro no mesmo commit.

### 44.2. Codificação e formato de arquivo
- Salvar sempre em UTF-8 e preservar as quebras de linha existentes do arquivo (o HTML principal usa CRLF).
- Após edições por script, procurar caracteres corrompidos (ex.: `s?o`, `Intelig?ncia`, `(A ? B) ? 100`) e restaurar os acentos e símbolos (`÷`, `×`, `—`).
- O console do Windows pode exibir `�` para caracteres válidos: confirmar no próprio arquivo (bytes/UTF-8) antes de "corrigir".

### 44.3. JavaScript
- **Sem declarações duplicadas:** antes de criar uma função, pesquisar `function nome(` no arquivo inteiro. Duas declarações globais com o mesmo nome fazem a última sobrescrever silenciosamente a primeira. Código substituído deve ser removido, não deixado como cópia morta.
- **Handlers inline válidos:** todo `onclick`/`onchange`/`oninput`, inclusive os gerados em template strings, deve chamar uma função existente com o nome exato (verificar por busca).
- **Funções reutilizáveis não podem ser IIFE nomeadas:** `(function nome(){...})()` não cria `nome` no escopo global. Declarar `function nome(){...}` e chamar `nome();` em seguida.
- **Scripts no `<head>`** não podem acessar `document.body` (ainda é `null`).
- **Variáveis `let`/`const` globais** usadas por funções chamadas cedo devem ser protegidas contra a zona morta temporal (ex.: `try { ... } catch (e) { ... }`).
- **Nulos e números:** usar `v != null` (cobre `null` e `undefined`) antes de `.toFixed()`; tratar `NaN` com `Number.isNaN`. A interface nunca pode exibir `null`, `undefined` ou `NaN`; usar `—`.
- **Funções com muitos parâmetros posicionais** (ex.: `card(sigla, nome, tipo, dados, formula, result, fonte, sup, ausente, badge)`): conferir a ordem dos argumentos em cada chamada e passar `null` explicitamente nas posições vazias.
- **Acesso a colunas por `indexOf`:** tratar o retorno `-1`. Usar um auxiliar que retorne `null` para colunas inexistentes; nunca usar `row[cols.indexOf('x')] || 0` quando a coluna pode não existir.
- **Requisições assíncronas:** reaproveitar a promessa em andamento (cache de requisições pendentes por chave) e, após cada `await`, verificar se o estado ainda é o mesmo (UF, nível, aba) antes de alterar o DOM.
- **Histórico:** chamar `history.pushState` apenas quando o hash de destino for diferente do atual, para não reempilhar entradas no Voltar/Avançar.
- **Listeners:** registrar uma única vez e preferir delegação no `document`; nunca adicionar listeners dentro de funções de renderização.
- **Segurança:** todo texto vindo do usuário (busca, nome de arquivo, mensagens de erro) inserido via `innerHTML` deve passar por `escHtml()`.
- **Gráficos Chart.js:** destruir (`.destroy()`) ou atualizar (`.update()`) a instância anterior antes de recriar.

### 44.4. Dados, escopo e textos interpretativos
- **Ausência de dado ≠ zero:** um dado inexistente deve ser exibido como `—` ou "Sem dados", nunca como `0` ou `0,0%`.
- **Proibido valor numérico fixo de indicador no código** (médias, benchmarks, "valores de reserva"). Valores de referência nacionais são sempre **calculados** a partir da base nacional consolidada (`DATA.nacional`) por `getNationalAverage(sigla)` e formatados por `formatIndicatorValue(ind, v)`; `ALL_INDICATORS[].valNac` é sincronizado por `syncNationalValues()`.
- Em qualquer escopo, a falta de dado não pode ser preenchida com valor de outro escopo nem com constante: exibir `—`.
- Município sem registro no SETE não pode herdar dados nacionais ou estaduais.
- **Textos interpretativos** (badges, tooltips, legendas, cartões) devem derivar do mesmo valor exibido do indicador, e não de colunas auxiliares que podem não existir.
- O nome da escala de cor na legenda deve vir da mesma função que define a cor do mapa (`getMapaTheme`).
- Mensagens da interface devem descrever o comportamento real (ex.: não afirmar "dados integrados" quando a planilha é apenas lida).
- Divergências entre valores do mesmo indicador em locais diferentes do código devem ser **relatadas** ao usuário, não corrigidas por julgamento próprio (§11 e §33).

### 44.5. HTML e acessibilidade
- Botões apenas com ícone: `type="button"` e `aria-label` descritivo (`title` sozinho não basta).
- Campos sem `<label>` visível: `aria-label`. Rótulos visíveis devem ter `for` apontando para o `id` do campo.
- Elementos clicáveis devem ser `<button>`. Quando não for possível (itens gerados de ranking, cabeçalhos expansíveis), usar `role="button"` e `tabindex="0"`; o listener delegado global já trata Enter/Espaço.
- Cabeçalhos expansíveis devem manter `aria-expanded` e `aria-controls` sincronizados com o estado.
- Modais: `role="dialog"`, `aria-modal="true"`, título associado (`aria-labelledby`) e fechamento por Esc.
- Links de navegação apontam para a seção real (`href="#secX"`), nunca `href="#"`.
- Imagens não podem usar fallback de domínio de terceiros (§6); `onerror` deve começar com `this.onerror=null`.

### 44.6. CSS e design system
- Antes de usar `var(--token)`, confirmar que o token está definido nos temas claro e escuro.
- Não usar o atalho `background:` em componentes que dependem de `background-image` (ex.: a seta de `.form-select`); usar `background-color`.
- Não usar o atalho `border:` em regras que precisam preservar estados de hover/foco; usar `border-width`/`border-style`.
- Estilos inline de layout (`grid-template-columns`, `min-width` fixo, cores) anulam media queries e temas: definir na classe.
- Verificar se existe redefinição posterior do mesmo seletor que anule um media query anterior.
- Toda fonte usada em `font-family` precisa estar carregada; preferir `var(--font-serif)` e as fontes já importadas.
- Evitar `!important`; quando inevitável, documentar o motivo.

### 44.7. Temas (light/dark)
- A plataforma suporta apenas `light` e `dark`. O valor legado `dim` é normalizado para `dark`.
- O tema salvo em `localStorage` (`pnite_theme`) é aplicado no `<head>`, antes da renderização, para evitar o flash do tema claro.
- Texto sobre fundos `--c-blue` no modo escuro deve usar `var(--c-navy)` (o azul escuro é claro demais para texto branco).
- Contraste mínimo de 4,5:1 para texto normal nos dois temas; cores de estado (sucesso/erro) precisam de variante para o modo escuro.

### 44.8. Responsividade
- `minmax()` em grades deve usar `min(Xpx, 100%)` para não estourar telas estreitas.
- Filhos de flex/grid que contêm texto longo ou `<select>` precisam de `min-width: 0` e `max-width: 100%`.
- Barras de navegação e grupos de pílulas longos usam rolagem horizontal controlada (`overflow-x: auto`) em telas ≤ 760px.
- Elementos interativos têm área mínima de 44×44px em `@media (pointer: coarse)`.
- Modais: `max-height: calc(100vh - 40px)` e `overflow-y: auto`.

### 44.9. Protocolo mínimo de verificação
1. **Sintaxe:** extrair cada bloco `<script>` e executar `node --check`.
2. **Duplicidades:** listar declarações `function nome(` de nível global e confirmar que não há nomes repetidos; listar `id="..."` estáticos repetidos.
3. **Navegador headless** (Chrome/Edge via `puppeteer-core`), carregando o arquivo local:
   - zero `pageerror` e zero erros de console no carregamento e durante as interações;
   - escopos Nacional, Região, Estado e Município, conferindo dashboard, mapa, tabelas SETE e memória de cálculo;
   - alternância de tema e persistência em `localStorage`;
   - navegação entre módulos e botão Voltar;
   - `document.documentElement.scrollWidth <= clientWidth` em 375px, 768px e 1280px, nos dois temas;
   - capturas de tela claro/escuro em desktop e celular para inspeção visual.
4. **Linha de base:** quando houver dúvida se um problema é novo ou pré-existente, executar o mesmo teste na versão anterior em `old/`.
5. Scripts de teste e arquivos temporários ficam fora do repositório (pasta temporária), salvo pedido explícito.

---

## 45. PASTA `upload/` — ENVIO DE PLANILHAS AO BANCO
A pasta `upload/` recebe as planilhas de capacitação e de outras fontes que devem ser enviadas ao Supabase.

- **Fora do Git:** o `.gitignore` ignora todo o conteúdo de `upload/`, exceto `upload/README.md`. As planilhas podem conter dados pessoais e nunca devem ser commitadas (§6), nem copiadas para outras pastas versionadas.
- **Envio genérico:** `python scripts/importar_planilha.py` lê todos os arquivos de `upload/` (inclusive subpastas; CSV, TSV, TXT, XLSX, XLSM, XLS, ODS) e cria uma tabela por arquivo no schema privado `importacao` (sem acesso pela API pública). Usar `--simular` antes de enviar e `--modo substituir` para reenviar.
- **Schemas protegidos:** o script recusa `public`, `sete`, `censo`, `analise` e `pnite_meta`. Dados de `upload/` só chegam à interface por views agregadas criadas em migração, nunca expondo dados pessoais.
- **Regras por planilha:** a estrutura esperada de cada planilha e o tratamento específico (tabela de destino, colunas, tipos, anonimização) serão definidos pelo usuário, planilha a planilha. Ao receber essas definições, registrá-las nesta seção (subseções 45.x) e implementá-las no script de envio, sem inferir estruturas não informadas.
