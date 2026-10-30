# DeliveryVip Developers (Mintlify)

Documentação de API da DeliveryVip, em português do Brasil, publicada com Mintlify. Migrada do GitBook (`../ApiDocs`) em outubro de 2026. Este repositório é a fonte da verdade.

## Comandos

```bash
npx mint dev --port 3333          # preview local
npx mint validate                 # build estrito; precisa passar
npx mint broken-links --check-anchors
```

`scripts/gitbook_to_mintlify.rb` foi a ferramenta de migração. **Não rode de novo**: ele regenera as páginas a partir do GitBook e apaga as edições feitas aqui.

## Estrutura

- `docs.json`: tema, navegação por produto (abas Início, Merchant API, Open Delivery, Fidelidade, Partner API, Changelog) e ícones dos grupos.
- `index.mdx`: home com o seletor de caminho.
- `inicio/`, `guides/<produto>/`, `reference/`: o caminho do arquivo é a URL. Não renomeie arquivos sem adicionar `redirects` no `docs.json`.
- A Referência de endpoints é gerada das specs em `https://app.deliveryvip.com.br/swaggers/*.yaml` (fonte: `../Platform/public/swaggers`).

## Estilo

Referência viva: as páginas de `guides/merchant/order/`.

- **Frontmatter**: `title`, `description` (uma frase sobre o que o leitor resolve na página), `icon` (Font Awesome) e `sidebarTitle` quando o título for longo.
- **Abertura**: um parágrafo curto dizendo para que serve a página. Sem H1 no corpo.
- **Fluxos** viram `<Steps>`; escolhas entre opções, `<Tabs>` ou `<CardGroup>`; dúvidas e troubleshooting, `<AccordionGroup>`.
- **Código**: toda chamada de endpoint em `<CodeGroup>` com cURL, Node.js (`fetch`) e Python (`requests`). Exemplos curtos e corretos. Token sempre `{token}` (nunca um JWT real), IDs de exemplo fictícios.
- **Campos** de request e response: `<ParamField>` / `<ResponseField>`, com `<Expandable>` para objetos aninhados. Tabelas grandes de enum podem continuar como tabela.
- **Callouts**: `<Tip>` atalhos, `<Info>` contexto, `<Warning>` o que quebra a integração, `<Danger>` perda de dados ou bloqueio, `<Check>` boas práticas e resultado esperado.
- **Diagramas**: Mermaid quando o fluxo for simples; imagens de `/images` ficam em `<Frame caption>`, sempre visíveis (nunca dentro de Accordion).
- **`.mintignore`**: o Mintlify publica qualquer `.md` e injeta em todas as páginas qualquer `.css`/`.js` do repositório. Tudo que não é página (scripts, fontes das artes, este arquivo) precisa estar no `.mintignore`.
- **Artes**: não usamos Mermaid. Os diagramas são PNGs gerados pelo kit em `scripts/art/` (`kit.js` + `kit.css`): cada um é uma especificação curta em `diagramas.html` (`render(id, "sequence" | "graph" | "timeline", spec)`), e a Jornada tem HTML próprio (`jornada-do-developer.html`). Para criar ou alterar: edite a especificação, sirva a pasta (`python3 -m http.server 8765` dentro de `scripts/art`), abra no navegador e capture o elemento `#<id>` em escala 2x para `images/<id>.png`. O `id` é o nome do arquivo da imagem. Capture também com `?theme=dark` para `images/<id>-dark.png` e use as duas na página: `<img className="block dark:hidden" src="/images/<id>.png" .../>` e `<img className="hidden dark:block" src="/images/<id>-dark.png" .../>`. Mantenha as artes com até ~1150px de largura para o texto continuar legível na coluna da página.
- **Idioma da interface**: a navegação fica dentro de `navigation.languages` com um único idioma `pt-BR` (traduz busca, "Na página" etc. sem mudar as URLs). O seletor de idioma, inútil com um idioma só, é escondido no `style.css`.
- **Fechamento**: cards de próximos passos quando fizer sentido; tabela de erros comuns em páginas de integração.
- Português claro e direto, frases curtas. Termos da API (`eventId`, `CREATED`) em código.
- MDX: escape `{`, `}` e `<` fora de código; links internos absolutos e sem extensão (`/guides/merchant/webhooks`).

## Exatidão

Nunca invente comportamento. Confira o que a página afirma no código do Platform (`../Platform`: rotas em `config/routes/`, controllers em `app/controllers/api/`, resources em `app/resources/api/`, specs em `public/swaggers/`). Quando a doc antiga divergir do código, documente o comportamento real e registre a divergência para revisão.
