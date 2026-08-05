# 🍱 BentoPDF (Kit de Ferramentas de PDF Self-Hosted atrás do Authelia)

Este guia sobe o **[BentoPDF](https://github.com/alam00000/bentopdf)**, um kit de ferramentas de PDF **open-source** com **100+ ferramentas** (juntar, dividir, girar, comprimir, converter de/para Office e imagens, editar, assinar digitalmente, carimbar, adicionar/remover senha, **OCR**, redigir, reorganizar páginas, extrair tabelas, comparar PDFs, entre outras).

A diferença fundamental para os editores de PDF tradicionais: **o BentoPDF não tem backend**. O container é só um **nginx servindo arquivos estáticos**, e **todo o processamento acontece dentro do seu navegador** (JavaScript + WebAssembly). Nenhum PDF é enviado ao servidor, nem para nuvem de terceiros: os arquivos nunca saem da sua máquina.

Como o app **não tem login próprio**, a **autenticação é delegada ao [Authelia + lldap](./authelia.md)** por trás do **[Caddy](./caddy.md)**: o container entra na rede `caddy-net` **sem publicar porta no host** e o acesso externo é via **Cloudflare Tunnel**, no mesmo padrão dos outros guias do repo.

**Pré-requisito:** Docker + Portainer ([./portainer-debian.md](./portainer-debian.md)) **e** as stacks **[authelia](./authelia.md)** e **[caddy](./caddy.md)** já no ar, que são elas que fazem o login.

A stack pronta está em [`assets/stacks/bentopdf.yml`](../assets/stacks/bentopdf.yml).

> [!IMPORTANT]
> **Use o build "Self-Hosted" (`bentopdf-simple`), não o comercial.** O BentoPDF publica duas
> imagens:
>
> - `ghcr.io/alam00000/bentopdf-simple:latest` (**esta stack**): todas as ferramentas de PDF, **sem**
>   a vitrine de marketing do bentopdf.com (hero, FAQ, depoimentos, rodapé). A doc oficial é
>   explícita: **não** é uma versão "lite", nenhuma ferramenta é removida.
> - `ghcr.io/alam00000/bentopdf:latest`: o site completo de marketing, usado pelo próprio
>   bentopdf.com e por quem roda um serviço público de PDF sob marca própria.
>
> Ambas são multi-arch (`linux/amd64` + `linux/arm64`), então rodam na VPS ARM sem QEMU.

> ⚠️ **Os módulos pesados vêm de CDN pública, baixados pelo NAVEGADOR.** Recursos avançados
> (conversão EPUB/MOBI/XPS, PDF/A, compressão, sumário, anexos) usam bibliotecas WebAssembly
> licenciadas em AGPL (PyMuPDF, Ghostscript, CoherentPDF) que **não são embutidas na imagem**: elas
> são buscadas em `cdn.jsdelivr.net` **pelo navegador do usuário**, em tempo de execução. O
> **servidor** não baixa nada, e **seus PDFs continuam sem sair da máquina**, mas a máquina do
> usuário precisa de internet na primeira vez que abre uma dessas ferramentas. Para ambiente
> isolado (air-gapped), veja [Notas Importantes](#notas-importantes).

> ℹ️ **Sem banco de dados, sem estado, sem OCR no servidor.** O OCR é o **Tesseract.js rodando no
> navegador**, então não existe mais aquela etapa de baixar `.traineddata` para o host. O único
> arquivo persistente é um `config.json` **opcional** (para esconder ferramentas da UI).

## Arquitetura

```
Navegador ──► https://pdf.selflabs.org
   └─► Cloudflare (termina o TLS) ──► cloudflared (bare metal no host) ──► Caddy :8080
        │
        ├─► forward-auth ──► Authelia (login + 2FA)      ◄── rede auth-net
        └─► (autorizado) ──► BentoPDF (nginx) :8080      ◄── rede caddy-net (SEM porta no host)
               └─► /srv/pdf/config.json  (opcional: esconder ferramentas)

O servidor só entrega HTML/JS/WASM. O PDF é aberto, processado e salvo
DENTRO do navegador: nada é enviado ao container.
```

**Portas no host:** o BentoPDF **não publica porta**, só `expose: 8080` na rede `caddy-net`. Quem publica (preso a `127.0.0.1:8080`, para o `cloudflared`) é o **Caddy**. Isso significa que o app **só** é alcançável depois de passar pelo Authelia.

> A imagem oficial usa o `nginx-unprivileged` (roda como UID 101, não root). Como não há dados de aplicação para gravar, **não é preciso ajustar dono de pasta** como nos outros guias.

---

## Parte 1: Preparar a Pasta de Dados

Seguindo o padrão `/srv`, crie a pasta e o `config.json` que a stack monta. Mesmo que você não vá esconder nenhuma ferramenta, **crie o arquivo com um JSON vazio**: um bind mount apontando para um arquivo inexistente faz o Docker criar uma **pasta** com aquele nome.

> ℹ️ A pasta é **`/srv/pdf`** (e não `/srv/bentopdf`) porque acompanha o hostname `pdf.selflabs.org` e reaproveita o diretório que já existia neste host. Se você está vindo do Stirling-PDF, faça a limpeza da [Parte 8](#parte-8-migração-vindo-do-stirling-pdf) em vez dos comandos abaixo.

```bash
sudo mkdir -p /srv/pdf
echo '{}' | sudo tee /srv/pdf/config.json

# o nginx lê o arquivo como UID 101 e o mount é read-only; basta ser legível
sudo chmod 644 /srv/pdf/config.json
```

> ⚠️ **Crie o arquivo _antes_ do Deploy.** Se o Portainer subir primeiro, `/srv/pdf/config.json` vira um **diretório** e o app recebe `403` ao tentar lê-lo. A correção é parar a stack, `sudo rmdir /srv/pdf/config.json`, recriar o arquivo e redeployar.

> 💡 **Não quer configuração nenhuma?** Você pode remover a linha do `volumes:` na stack. O BentoPDF funciona sem o `config.json`, ele é puramente opcional (ver [Parte 5](#parte-5-esconder-ferramentas-opcional)).

## Parte 2: A Stack (Deploy)

O arquivo [`bentopdf.yml`](../assets/stacks/bentopdf.yml) define **um único serviço**: a imagem oficial `ghcr.io/alam00000/bentopdf-simple:latest`, `expose: 8080` na rede externa `caddy-net` (**sem porta no host**) e `healthcheck` na raiz do nginx. Não há porta publicada, banco, nem volume de dados de aplicação: o container é só um servidor de arquivos estáticos.

### Deploy via Portainer (Stack)

1. Acesse o Portainer → **Stacks** → **Add Stack**.
2. **Nome:** `bentopdf`.
3. Cole o conteúdo de [`assets/stacks/bentopdf.yml`](../assets/stacks/bentopdf.yml) no **Web editor** (ou aponte para o repositório Git).
4. Na aba **Environment variables** (no Portainer **não** se usa arquivo `.env`): **nada obrigatório**. Esta stack não tem nenhum segredo.
5. Clique em **Deploy the stack**.

> ⚠️ **A rede `caddy-net` precisa existir** (`docker network create caddy-net`), ela é criada junto com a stack **[caddy](./caddy.md)**. Sem ela o deploy falha com `network caddy-net not found`.

> 🐚 **Alternativa via SSH (sem Portainer):** `docker compose -f bentopdf.yml up -d`.

### Variáveis de ambiente disponíveis

O BentoPDF é um site estático: quase toda a configuração é **de build**, e só um punhado de variáveis vale em **runtime** (ou seja, funciona colando na stack do Portainer):

| Variável         | O que faz                                                     | Padrão  |
| :--------------- | :------------------------------------------------------------- | :------ |
| `PORT`           | Porta que o nginx escuta dentro do container                  | `8080`  |
| `DISABLE_IPV6`   | Desliga o listener IPv6 do nginx (host com IPv6 desabilitado) | `false` |
| `ROBOTS_NOINDEX` | **Não use nesta imagem**, ver aviso abaixo                    | `false` |

> [!WARNING]
> **`ROBOTS_NOINDEX=true` derruba o container na imagem padrão.** O script
> `/docker-entrypoint.d/98-noindex.sh` roda `sed -i` sobre os HTML em
> `/usr/share/nginx/html`, e o `sed -i` precisa criar um arquivo temporário **dentro do
> diretório**. No `nginx-unprivileged` (UID 101) o `COPY --chown` deixou só os **arquivos**
> como `nginx`: o **diretório** continua `root`. Resultado:
> `sed: can't create temp file '/usr/share/nginx/html/index.htmlXXXXXX': Permission denied`,
> o entrypoint aborta e o container entra em **loop de restart**. A variável só funciona no
> `Dockerfile.nonroot`, cujo entrypoint dá `chown -R` no diretório antes de dropar privilégios.
>
> Para marcar a instância como não indexável, faça no **Caddy**, que é mais limpo e não
> depende da imagem. No bloco de `pdf.selflabs.org` do
> [Caddyfile](../assets/configs/caddy-Caddyfile):
>
> ```caddy
> header X-Robots-Tag "noindex, nofollow"
> ```
>
> (na prática é redundante aqui: o app já está atrás do Authelia e de um Cloudflare Tunnel,
> então nenhum crawler chega nele.)

Tudo o mais (idioma padrão, marca própria, URLs de WASM/OCR internos, `BASE_URL` em subpasta, lista de ferramentas desabilitadas via `DISABLE_TOOLS`) só existe como **build arg**: exige compilar a sua própria imagem a partir do repositório oficial. As duas exceções úteis sem rebuild são o **idioma** (o usuário troca na própria UI) e a **lista de ferramentas escondidas** (via `config.json`, [Parte 5](#parte-5-esconder-ferramentas-opcional)).

## Parte 3: Autenticação (Authelia) e exposição externa

O BentoPDF **não tem login próprio**. Quem barra o acesso é o **[Authelia](./authelia.md)**, e o roteamento é do **[Caddy](./caddy.md)**:

- No **[Caddyfile](../assets/configs/caddy-Caddyfile)** já existe o bloco de `pdf.selflabs.org` com `import authelia` + `reverse_proxy bentopdf:8080`.
- No **[Authelia](../assets/configs/authelia.yml)** já existe a regra `pdf.selflabs.org` no `access_control` (por padrão `one_factor` = só senha; troque para `two_factor` se quiser exigir TOTP também).

**No `cloudflared`** (bare metal no host), publique o hostname apontando para o **Caddy**, não para o BentoPDF:

1. Painel **Cloudflare One** (Zero Trust) → **Networks → Tunnels** → seu tunnel → **Public Hostname** → **Add**:
   - **Subdomain/Domain:** `pdf.selflabs.org`
   - **Service:** `HTTP` → `localhost:8080` **(o Caddy)**
2. O Cloudflare termina o TLS na borda; Caddy e BentoPDF falam **HTTP puro** internamente.

> [!WARNING]
> **Não sirva o BentoPDF em HTTP puro para o usuário final.** As conversões de Office (Word, Excel,
> PowerPoint, ODT) usam o **LibreOffice em WebAssembly**, que depende de `SharedArrayBuffer`. O
> navegador só libera isso quando a página é **contexto seguro** (`https://…` ou
> `http://localhost`) **e** recebe os headers `Cross-Origin-Opener-Policy` e
> `Cross-Origin-Embedder-Policy`. A imagem oficial já envia os dois headers, e o Cloudflare entrega
> `https://` ao navegador, então **este setup funciona**. O que **não** funciona é abrir por
> `http://IP-da-LAN:porta`: ali o navegador desabilita o `SharedArrayBuffer` e a conversão trava,
> sem correção possível via header.

> 🔒 O Cloudflare Access **não** é necessário: quem autentica é o Authelia (self-hosted). Túnel para expor, Authelia para logar.

## Parte 4: Primeiro Acesso e Idioma

1. Abra `https://pdf.selflabs.org`. Sem sessão, o Authelia redireciona para o portal `auth.selflabs.org`.
2. Faça login com um **usuário do lldap** (criado na UI `users.selflabs.org`, ver [authelia.md → Bootstrap](./authelia.md#parte-4-bootstrap--criar-o-bind-do-authelia-e-seu-usuário)). No sucesso, você cai **direto na grade de ferramentas**, sem segunda tela de login.
3. **Criar/remover usuários** é no **lldap** (`users.selflabs.org`), não no BentoPDF. Um login cobre todos os `*.selflabs.org` (SSO).
4. **Idioma:** a UI abre em inglês por padrão. Troque para **Português** no seletor de idioma da própria interface (a escolha fica salva no navegador). O idioma padrão de fábrica (`VITE_DEFAULT_LANGUAGE=pt`) só muda recompilando a imagem.
5. Teste o **OCR**: abra a ferramenta de OCR, envie um PDF escaneado e selecione **Portuguese**. O idioma é baixado pelo navegador na hora, sem nada a preparar no servidor. 🚀

> 💡 **Confirme que o modo avançado está liberado.** Abra o DevTools (F12) → Console e rode `window.crossOriginIsolated`. Tem que responder `true`: é isso que habilita as conversões de Office.

## Parte 5: Esconder Ferramentas (opcional)

Com 100+ ferramentas na tela, dá para enxugar a lista (ou tirar do ar recursos sensíveis como redação e assinatura) **sem rebuild**, editando o `/srv/pdf/config.json` criado na [Parte 1](#parte-1-preparar-a-pasta-de-dados).

O **ID da ferramenta** é o final da URL dela, sem o `.html` (a ferramenta em `…/edit-pdf.html` tem ID `edit-pdf`).

```bash
sudo tee /srv/pdf/config.json >/dev/null <<'JSON'
{
  "disabledTools": ["digital-sign-pdf", "prepare-pdf-for-ai"],
  "editorDisabledCategories": ["redaction"]
}
JSON
```

- `disabledTools`: some da home, da busca, dos atalhos e do construtor de workflows. Acesso direto pela URL mostra uma página de "ferramenta indisponível".
- `editorDisabledCategories`: desliga recursos **dentro** do editor de PDF (por exemplo `redaction`, `annotation-stamp`, `form`) sem tirar o editor inteiro. Categorias são hierárquicas: desabilitar `annotation` derruba todos os filhos.

Depois de editar, **reinicie o container** (o arquivo é lido pelo navegador a cada carga, mas o cache do nginx é de 1 semana para `.json`; um `Ctrl+F5` também resolve).

> ℹ️ A lista completa de IDs de ferramentas e de categorias do editor está na [documentação oficial do Docker](https://github.com/alam00000/bentopdf/blob/main/docs/self-hosting/docker.md#disabling-specific-tools).

## Parte 6: Atualização

A imagem usa a tag rolling `ghcr.io/alam00000/bentopdf-simple:latest`.

**Via Portainer (recomendado):**

1. Portainer → **Stacks** → `bentopdf`.
2. Clique em **Editor** (ou **Update the stack**) e marque **`Re-pull image and redeploy`**.
3. Clique em **Update the stack**. Sem marcar isso, o Redeploy comum **reusa o cache** e não baixa a imagem nova.

**Via SSH:**

```bash
docker compose -f bentopdf.yml pull
docker compose -f bentopdf.yml up -d
```

> 🔒 **Quer reprodutibilidade?** Fixe a versão na imagem (ex.: `ghcr.io/alam00000/bentopdf-simple:1.15.4`) e, para atualizar, bump a tag. O projeto publica tags versionadas junto com a `:latest`.

> ⚠️ **Atualizar não custa nada aqui.** Como não existe banco nem migração, trocar de versão é trocar arquivos estáticos. Se algo quebrar, voltar para a tag anterior resolve na hora.

## Parte 7: Backup

Praticamente não há o que fazer backup: o BentoPDF é **stateless**. O único arquivo seu é o `config.json`.

```bash
# snapshot completo do que é seu
sudo tar czf bentopdf-backup-$(date +%F).tar.gz -C /srv bentopdf
```

> 💾 Seus **PDFs nunca ficam no servidor**: eles são abertos e salvos direto no navegador. O backup dos seus documentos é o backup da sua própria máquina, não deste container.

## Parte 8: Migração vindo do Stirling-PDF

Se este host rodava o **Stirling-PDF** no mesmo `pdf.selflabs.org`, a troca é direta. A pasta `/srv/pdf` é **reaproveitada**: ela deixa de guardar estado de aplicação e passa a ter só o `config.json`.

1. Portainer → **Stacks** → `stirling-pdf` → **Remove**. Faça isso **primeiro**: com o container de pé, o Docker recria as pastas assim que você apagá-las.
2. Esvazie a pasta e deixe só o arquivo que a stack nova monta:

```bash
# nada aqui tem equivalente no BentoPDF
sudo rm -rf /srv/pdf/config /srv/pdf/logs /srv/pdf/pipeline /srv/pdf/tessdata /srv/pdf/customFiles

# o único arquivo da stack nova
echo '{}' | sudo tee /srv/pdf/config.json
sudo chmod 644 /srv/pdf/config.json
```

3. Suba a stack `bentopdf` ([Parte 2](#parte-2-a-stack-deploy)).
4. Ajuste o **[Caddyfile](../assets/configs/caddy-Caddyfile)** em `/srv/caddy/Caddyfile`: o bloco de `pdf.selflabs.org` passa a apontar para `reverse_proxy bentopdf:8080`. Recarregue com `docker restart caddy` (o `caddy reload` **não** funciona nesta stack: o `admin off` desliga a API na `:2019`, ver [caddy.md → Parte 5](./caddy.md#parte-5-atualizar)).
5. A regra do **Authelia** para `pdf.selflabs.org` **não muda**: o domínio é o mesmo.

> ⚠️ **O que morre junto com o Stirling.** `config/` era o `settings.yml` e o estado do Spring Boot; `logs/` era o log da aplicação; `tessdata/` eram os `.traineddata` do OCR; `pipeline/` guardava as automações criadas pela UI. Nada disso migra: a configuração do BentoPDF é build-time, o log vai para o `docker logs` e o OCR roda no navegador. **`pipeline/` é o único conteúdo autoral** ali. Se você chegou a montar automações, confira antes com `ls -lah /srv/pdf/pipeline`.

> ℹ️ **O que muda na prática:** acabam o consumo de RAM do Java + LibreOffice no servidor, o download dos idiomas de OCR e o `chown` de `/srv`. Em troca, o trabalho pesado passa a rodar na máquina de quem usa, e a primeira abertura de cada ferramenta avançada baixa o WASM correspondente da CDN.

---

## Troubleshooting

| Sintoma                                                              | Causa provável / Correção                                                                                                                                                                                                                       |
| :------------------------------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Conversão Word/Excel/PPT trava** (~55%) ou `SharedArrayBuffer is not defined` | A página não está cross-origin isolada. Rode `window.crossOriginIsolated` no Console: se der `false`, você abriu por HTTP puro (ex.: `http://192.168.x.x`) ou um proxy externo removeu os headers `Cross-Origin-Opener-Policy` / `Cross-Origin-Embedder-Policy`. Acesse pelo `https://pdf.selflabs.org` (via Caddy + Cloudflare) e não pelo IP da LAN. |
| **Ferramenta avançada falha** (EPUB/MOBI, PDF/A, comprimir, sumário) | O navegador não conseguiu buscar o módulo WASM em `cdn.jsdelivr.net`. Verifique a internet **da máquina do usuário** (o servidor não participa) e se algum bloqueador de DNS/anúncio está barrando a CDN.                                        |
| Container reinicia com `socket() [::]:8080 failed`                    | Host com IPv6 desabilitado no kernel. Adicione `DISABLE_IPV6: "true"` nas env vars da stack e redeploy.                                                                                                                                          |
| Loop de restart com `sed: can't create temp file '/usr/share/nginx/html/index.htmlXXXXXX': Permission denied` | `ROBOTS_NOINDEX=true` na imagem padrão. O `sed -i` do script de noindex não consegue gravar no diretório (dono `root`) e o entrypoint aborta. **Remova a variável** da stack e redeploy; use `header X-Robots-Tag` no Caddy se precisar do noindex ([Variáveis de ambiente](#variáveis-de-ambiente-disponíveis)). |
| Log do app reclamando de `config.json` / `403`                        | O bind mount virou pasta. Pare a stack, `sudo rmdir /srv/pdf/config.json`, recrie o arquivo com `echo '{}' \| sudo tee /srv/pdf/config.json` ([Parte 1](#parte-1-preparar-a-pasta-de-dados)) e redeploy.                              |
| **502 / Bad Gateway** em `pdf.selflabs.org`                           | App fora da `caddy-net`, nome de container errado no Caddyfile (tem que ser `bentopdf`), ou o Authelia caído. Confirme com `docker network inspect caddy-net` e que o `authelia` está `Up`.                                                      |
| Redireciona pro `auth.` e não volta                                   | Problema no forward-auth/`X-Forwarded-Proto`. Ver [caddy → Troubleshooting](./caddy.md#troubleshooting).                                                                                                                                        |
| **Assinar PDF / preencher formulário** mostra viewer em branco        | MIME de `.mjs` servido como `application/octet-stream`. A imagem oficial já trata isso; se aparecer, algum proxy/CDN na frente está re-farejando o tipo. Confira o `Content-Type` da requisição `.mjs` no DevTools → Network.                    |
| Arquivo grande trava ou o navegador fica sem memória                  | O processamento é **local**: o limite é a RAM da máquina do usuário, não do servidor. Feche abas, use uma máquina com mais memória ou divida o PDF antes.                                                                                        |
| Editei o `config.json` e nada mudou                                   | Cache. Reinicie o container e/ou faça `Ctrl+F5` no navegador ([Parte 5](#parte-5-esconder-ferramentas-opcional)).                                                                                                                               |
| A UI aparece em inglês                                                | Normal: o padrão de fábrica é `en`. Troque no seletor de idioma da própria UI ([Parte 4](#parte-4-primeiro-acesso-e-idioma)); mudar o padrão exige rebuild da imagem.                                                                            |

---

## Notas Importantes

- **Privacidade de verdade:** o processamento é **100% no navegador** (JS + WebAssembly). Nenhum PDF é enviado ao container, então nem um servidor comprometido veria seus documentos. É o principal motivo para preferir o BentoPDF a um editor de PDF com backend.
- **Autenticação externa:** o app roda **aberto**; quem protege é o **[Authelia](./authelia.md)** no forward-auth do **[Caddy](./caddy.md)**. Como o container **não publica porta**, ele só é alcançável depois do login. Nunca exponha a porta `8080` do BentoPDF direto no host.
- **Consumo no servidor é irrisório:** é nginx servindo estáticos (~100 MB em disco, dezenas de MB de RAM). Comparado a um editor de PDF com backend Java, some a necessidade de folga de RAM no host: a carga real fica na máquina de quem usa.
- **Módulos AGPL via CDN:** PyMuPDF, Ghostscript e CoherentPDF **não** são embutidos na imagem, são carregados de `cdn.jsdelivr.net` pelo navegador em tempo de execução. Isso mantém a fronteira de licença clara e deixa a imagem pequena, mas significa que uma rede **totalmente isolada** precisa hospedar esses WASM internamente e **recompilar** a imagem com `--build-arg VITE_WASM_*_URL=…` (as URLs são gravadas no bundle em tempo de build, e a CSP é gerada a partir delas).
- **Licença dupla (AGPL-3.0 / comercial):** rodar como **ferramenta interna, sem redistribuir**, está coberto pela AGPL-3.0 e é gratuito. A licença comercial só entra em cena para produto proprietário, SaaS de terceiros ou redistribuição sem abrir o código.
- **Configuração é quase toda build-time:** marca própria, idioma padrão, subpasta (`BASE_URL`) e `DISABLE_TOOLS` exigem compilar a própria imagem. Em runtime você tem `PORT`, `DISABLE_IPV6`, `ROBOTS_NOINDEX` e o `config.json`.
- **Sem estado, sem migração:** não há banco, sessão nem usuário no app. Atualizar, recriar ou mover o container é indolor.
- **OCR no navegador:** Tesseract.js baixa o idioma sob demanda. Não existe mais pasta `tessdata` no host para manter.

---

## Acessos

| Recurso                | URL / Local                               |
| :--------------------- | :---------------------------------------- |
| **Web UI (público)**   | `https://pdf.selflabs.org` (via Authelia) |
| **Gestão de usuários** | `https://users.selflabs.org` (lldap)      |
| **Portal de login**    | `https://auth.selflabs.org` (Authelia)    |
| **Portainer**          | Stack `bentopdf`                          |
| **Dados (host)**       | `/srv/pdf`                           |
| **Config opcional**    | `/srv/pdf/config.json`               |

---

## Referências

- [BentoPDF: Repositório oficial (GitHub)](https://github.com/alam00000/bentopdf)
- [BentoPDF: Documentação](https://www.bentopdf.com/docs/)
- [BentoPDF: Deploy com Docker / Podman](https://github.com/alam00000/bentopdf/blob/main/docs/self-hosting/docker.md)
- [BentoPDF: Guia de Self-Hosting (WASM, air-gapped, requisitos)](https://github.com/alam00000/bentopdf/blob/main/docs/self-hosting/index.md)
- [BentoPDF: Simple Mode (build Self-Hosted)](https://github.com/alam00000/bentopdf/blob/main/SIMPLE_MODE.md)
- [BentoPDF: Licenciamento (AGPL-3.0 / comercial)](https://github.com/alam00000/bentopdf/blob/main/docs/licensing.md)
- [Authelia + lldap (este repo)](./authelia.md) · [Caddy (este repo)](./caddy.md)
