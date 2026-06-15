# 📝 FrankMD (Notas em Markdown Self-Hosted via Docker + Cloudflare Tunnel)

Este guia sobe o **FrankMD** (_Frank Markdown_) — um app de notas em **Markdown** self-hosted feito em **Ruby on Rails 8**, criado pelo [AkitaOnRails](https://github.com/akitaonrails/FrankMD). O grande diferencial é que ele **não usa banco de dados**: cada nota é um arquivo `.md` comum no seu disco, então seus dados ficam sempre legíveis, versionáveis com Git e fáceis de fazer backup. Traz editor com preview GitHub-flavored, organização em pastas, modo _typewriter_, suporte a posts do Hugo, busca embutida e recursos opcionais de IA (correção gramatical e geração de imagem). A stack usa **Docker** (container único, sem DB), idioma **pt-BR** e exposição via **Cloudflare Tunnel + Access**, com tudo centralizado em `/srv`, no mesmo padrão dos outros guias do repo.

**Pré-requisito:** Docker Engine + Docker Compose instalados. Se ainda não tem, veja o guia [Docker + Portainer no Debian](./portainer-debian.md). Para o acesso externo, assume-se um `cloudflared` já rodando **bare metal no host** (você só adiciona o subdomínio pelo painel do Cloudflare One — ver [Parte 4](#parte-4-acesso-externo-via-cloudflare-tunnel--access)).

A stack pronta está em [`assets/stacks/frankmd.yml`](../assets/stacks/frankmd.yml).

> [!WARNING]
> **O FrankMD não tem login/autenticação própria.** O app é _sessionless_ — a sessão só guarda preferências de UI, não existe usuário/senha. Ou seja: **qualquer um que alcançar a porta edita e apaga suas notas.** Nunca exponha o FrankMD direto na internet: use **Cloudflare Access** como camada de senha (Parte 4) ou mantenha o acesso só na **LAN**.

## Arquitetura

```
┌─ INTERNET ────────────────────────────────────────────────────────┐
│                                                                   │
│  Navegador                                                        │
│  ──► https://notas.exemplo.com                                    │
│  ──► Cloudflare Edge (termina o TLS)                              │
│  ──► Cloudflare Access (login/OTP — a "senha" do app)             │
│  ──► Tunnel (cloudflared bare metal no host)                      │
│  ──► localhost:7591 ──► FrankMD (Thruster :80 -> Puma, HTTP puro) │
│         │                                                         │
│         └──► /srv/frankmd/notes (.md)  +  /srv/frankmd/images     │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

**Portas no host:**

| Porta Host | Porta Container | Uso                                                                                                                            |
| :--------- | :-------------- | :----------------------------------------------------------------------------------------------------------------------------- |
| `7591/tcp` | `80`            | FrankMD (Web UI) — alvo do `cloudflared` e da LAN. Dentro do container, o **Thruster** escuta na `80` e faz proxy para o Puma. |

> Não há banco de dados nem porta interna extra: o FrankMD lê e grava as notas diretamente em `/rails/notes` (bind mount), reduzindo a superfície a um único serviço.

---

## Parte 1: Preparar as Pastas de Dados

Seguindo o padrão `/srv`, crie as pastas onde o FrankMD vai persistir as notas e as imagens.

```bash
sudo mkdir -p /srv/frankmd/notes /srv/frankmd/images

# o container roda como o usuario UID/GID 1000 (padrao da stack);
# as pastas precisam ser dele, senao da EACCES ao gravar as notas
sudo chown -R 1000:1000 /srv/frankmd
```

> `notes` guarda as notas em `.md` (o **dado real** do app) e também o arquivo de configuração `.fed`. `images` guarda as imagens locais (opcional). Faça backup de `/srv/frankmd` inteiro e você tem tudo — ver [Parte 7](#parte-7-backup).

> ℹ️ **UID/GID diferente de 1000?** Se o seu usuário do host não for `1000`, descubra com `id -u` / `id -g`, ajuste o `chown` acima e defina `FRANKMD_UID`/`FRANKMD_GID` nas env vars do Portainer (a stack usa `1000` por padrão).

## Parte 2: Configurar os Segredos e Chaves de API

A stack lê os segredos por `${VAR}` — **nunca** hardcode no compose. No Portainer eles vão na aba **Environment variables** (Parte 3); via SSH, num arquivo `.env` ao lado do compose.

### 2.1 — `FRANKMD_SECRET_KEY_BASE` (obrigatório recomendado)

Chave do Rails que assina os cookies de preferência da UI. Gere uma string aleatória forte:

```bash
openssl rand -hex 64
```

> ℹ️ Se você **não** definir essa variável, o FrankMD gera uma aleatória a cada boot — o app funciona, mas suas **preferências de UI** (tema, idioma escolhido na tela, etc.) são esquecidas a cada redeploy. Como o app **não tem autenticação nem dados sensíveis em sessão**, essa chave é bem menos crítica que a de outros guias; ainda assim, **fixe uma** para a experiência ficar estável.

### 2.2 — IA: `GEMINI_API_KEY` (correção gramatical / geração de imagem)

A stack já vem com `AI_PROVIDER=gemini` e `GEMINI_MODEL=gemini-3.1-flash-lite`. Só falta a chave:

1. Acesse o **Google AI Studio** → [aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey).
2. **Create API key** e copie o valor para `GEMINI_API_KEY`.

> ⚠️ A chave do **AI Studio** (Gemini) é diferente das chaves do **Google Cloud Console** (YouTube/Imagens) abaixo — não confunda.

### 2.3 — Busca no YouTube: `YOUTUBE_API_KEY`

1. No **Google Cloud Console** → [console.cloud.google.com](https://console.cloud.google.com/) → crie/abra um projeto.
2. **APIs & Services** → **Enable APIs** → habilite **YouTube Data API v3**.
3. **Credentials** → **Create credentials** → **API key** → copie para `YOUTUBE_API_KEY`.

### 2.4 — Busca de imagens na web (já incluída — sem chave)

**Você não precisa configurar nada para buscar imagens.** O FrankMD já traz busca de imagens **gratuita via DuckDuckGo e Pinterest** embutida no editor (sem chave de API). Soma-se a isso a **geração de imagem por IA** (Gemini, configurado na Parte 2.2) e o **navegador de imagens locais** (pasta `/srv/frankmd/images`).

> [!WARNING]
> **A aba "Google Images" foi descontinuada na prática — por isso não usamos `GOOGLE_API_KEY`/`GOOGLE_CSE_ID`.** Ela dependia de um Custom Search Engine com **"Pesquisar em toda a Web"**, recurso que o Google [**encerrou**](https://support.google.com/programmable-search/answer/12397162); além disso, a **Custom Search JSON API está fechada para novos clientes** e será **desligada em 1º/01/2027**. O substituto oficial (**Vertex AI Search**) só pesquisa domínios específicos (até 50) e é outro produto do Google Cloud — busca na web inteira virou solução sob contato/paga. Como a busca de imagens já funciona de graça pelo DuckDuckGo, não compensa o esforço.

### Resumo das variáveis

| Variável                      | Obrigatória? | O que é                          | Onde obter                                     |
| :---------------------------- | :----------- | :------------------------------- | :--------------------------------------------- |
| `FRANKMD_SECRET_KEY_BASE`     | Recomendada  | Chave Rails (cookies de UI)      | `openssl rand -hex 64`                         |
| `GEMINI_API_KEY`              | Opcional     | IA (gramática/imagem)            | Google **AI Studio**                           |
| `YOUTUBE_API_KEY`             | Opcional     | Busca de vídeos                  | Google **Cloud Console** → YouTube Data API v3 |
| `FRANKMD_UID` / `FRANKMD_GID` | Opcional     | UID/GID do host (default `1000`) | `id -u` / `id -g`                              |

> As integrações de IA e busca são **opcionais**: deixe a chave em branco e o recurso correspondente simplesmente fica desligado, sem quebrar o app.

## Parte 3: A Stack (Deploy)

O arquivo [`frankmd.yml`](../assets/stacks/frankmd.yml) define **um único serviço**: a imagem oficial `akitaonrails/frankmd:latest`, rodando como UID/GID `1000`, expondo a porta `7591` (Web UI) e persistindo notas/imagens em `/srv/frankmd`. Tem `healthcheck` no endpoint `/up` do Rails.

### Deploy via Portainer (Stack)

1. Acesse o Portainer → **Stacks** → **Add Stack**.
2. **Nome:** `frankmd`.
3. Cole o conteúdo de [`assets/stacks/frankmd.yml`](../assets/stacks/frankmd.yml) no **Web editor**.
4. Na aba **Environment variables**, adicione (no Portainer **não** se usa o arquivo `.env`):
   - `FRANKMD_SECRET_KEY_BASE` — a chave gerada na [Parte 2](#parte-2-configurar-os-segredos-e-chaves-de-api).
   - `GEMINI_API_KEY`, `YOUTUBE_API_KEY` — se for usar IA e busca de vídeos (a busca de imagens é gratuita, sem chave).
   - `FRANKMD_UID` / `FRANKMD_GID` — só se o seu usuário não for `1000`.
5. Clique em **Deploy the stack**.

> ⚠️ **Crie as pastas da [Parte 1](#parte-1-preparar-as-pastas-de-dados) via SSH _antes_ do Deploy.** Se o Portainer subir primeiro, o Docker cria `/srv/frankmd/*` como `root` e o FrankMD (uid 1000) não consegue gravar as notas (`EACCES`).

> 🐚 **Alternativa via SSH (sem Portainer):** com o `.env` preenchido ao lado do compose, rode `docker compose -f frankmd.yml up -d`.

## Parte 4: Acesso Externo via Cloudflare Tunnel + Access

Como o `cloudflared` já roda **bare metal no host**, basta publicar um hostname novo — **a stack não leva sidecar de cloudflared** (a seção comentada no compose original do projeto fica de fora, por convenção do repo).

1. No painel **Cloudflare One** (Zero Trust) → **Networks → Tunnels** → seu tunnel → aba **Public Hostname** → **Add a public hostname**:
   - **Subdomain/Domain:** `notas.exemplo.com`
   - **Service:** `HTTP` → `localhost:7591` (ou `IP_DO_HOST:7591`)
2. O Cloudflare termina o TLS na borda; o container do FrankMD roda **HTTP puro** internamente (não precisa de protocolo `https` em lugar nenhum da stack).

> [!WARNING]
> **Proteja a rota com Cloudflare Access — isto não é opcional aqui.** Como o FrankMD **não tem login próprio**, o Access vira a senha do app. Em **Cloudflare One → Access → Applications → Add an application → Self-hosted**:
>
> - **Application domain:** `notas.exemplo.com`
> - **Policy:** ex. _Allow_ → **Emails** = o seu e-mail (ou um grupo). Use OTP por e-mail, Google, GitHub, etc.
>
> Sem essa política, qualquer pessoa com o link tem acesso total de escrita às suas notas.

## Parte 5: Primeiro Acesso e Configuração

1. Acesse `https://notas.exemplo.com` (passando pelo Access) ou, na LAN, `http://IP_DO_HOST:7591`.
2. Não há tela de cadastro — você já cai direto no editor. A interface já vem em **português (pt-BR)** porque a stack define `FRANKMD_LOCALE=pt-BR`.
3. Comece a criar notas. Cada nota vira um arquivo `.md` em `/srv/frankmd/notes`. 🚀

> ℹ️ **O arquivo `.fed`:** a configuração do FrankMD (preferências de UI, caminhos, chaves de API editadas pela tela) fica num arquivo `.fed` dentro do diretório de notas — então ela viaja junto no backup. As **env vars da stack têm precedência** e são a forma recomendada de definir os segredos; o `.fed` é útil para ajustes feitos direto pelo app.

> 💡 **Posts de Hugo:** o FrankMD entende a estrutura de _blog posts_ do Hugo (front matter, slug, shortcode de YouTube). Se você publica um site Hugo, dá para escrever e organizar os posts aqui mesmo.

## Parte 6: Atualização

A imagem usa a tag rolling `akitaonrails/frankmd:latest`.

**Via Portainer (recomendado):**

1. Portainer → **Stacks** → `frankmd`.
2. Clique em **Editor** (ou **Update the stack**) e marque **`Re-pull image and redeploy`**.
3. Clique em **Update the stack**. Sem marcar isso, o Redeploy comum **reusa o cache** e não baixa a imagem nova.

**Via SSH:**

```bash
docker compose -f frankmd.yml pull
docker compose -f frankmd.yml up -d
```

> 💾 As notas e imagens ficam nos bind mounts `/srv/frankmd/*` (no host), então atualizar/recriar o container **não apaga** nada.

> 🔒 **Quer reprodutibilidade?** Fixe a versão na imagem (ex.: `akitaonrails/frankmd:<tag>`) e, para atualizar, bump a tag — assim você sempre sabe qual versão está rodando.

## Parte 7: Backup

O backup do FrankMD é **trivial** justamente por não ter banco de dados: tudo é arquivo.

```bash
# snapshot completo (notas + imagens + .fed)
sudo tar czf frankmd-backup-$(date +%F).tar.gz -C /srv frankmd
```

> 💾 Copiar `/srv/frankmd` inteiro já captura tudo. Como as notas são `.md` puros, uma alternativa elegante é **versioná-las com Git** (`git init` dentro de `/srv/frankmd/notes`) e empurrar para um repositório privado — você ganha histórico, diff e restauração por commit. Lembre de guardar também o `FRANKMD_SECRET_KEY_BASE` no seu cofre de segredos.

---

## Troubleshooting

| Sintoma                                          | Causa provável / Correção                                                                                                                                                       |
| :----------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `Permission denied` / `EACCES` ao salvar notas   | As pastas são de `root`. Pare a stack e rode `sudo chown -R 1000:1000 /srv/frankmd` (Parte 1).                                                                                  |
| Container não sobe / erro ao bindar a porta `80` | Raro: a imagem usa **Thruster** e roda como uid 1000 normalmente. Se ocorrer `permission denied` no bind, remova temporariamente `no-new-privileges:true` do compose e reporte. |
| **502 / Bad Gateway** no domínio do túnel        | Public Hostname apontando para serviço/porta errados. Use `HTTP` → `localhost:7591` (Parte 4).                                                                                  |
| Qualquer um abre e edita as notas                | Falta a política do **Cloudflare Access**. Configure a Application em Zero Trust (Parte 4) ou restrinja à LAN.                                                                  |
| Correção gramatical/IA não funciona              | `GEMINI_API_KEY` ausente/errada ou modelo inválido. Use a chave do **AI Studio** (não a do Cloud Console) e confira `GEMINI_MODEL`.                                             |
| Busca de **vídeos** (YouTube) vem vazia          | `YOUTUBE_API_KEY` ausente ou *YouTube Data API v3* não habilitada no **Cloud Console** (Parte 2.3). A busca de **imagens** usa DuckDuckGo/Pinterest e **não** precisa de chave. |
| Preferências de UI somem a cada redeploy         | `SECRET_KEY_BASE` está sendo autogerada. Fixe `FRANKMD_SECRET_KEY_BASE` (Parte 2.1).                                                                                            |

---

## Notas Importantes

- **Sem banco de dados:** as notas são arquivos `.md` no host. Isso torna o backup e a portabilidade triviais (copie a pasta ou versione com Git) e mantém seus dados sempre legíveis fora do app.
- **Sem autenticação (segurança):** o app é _sessionless_. **Sempre** o coloque atrás do **Cloudflare Access** (Parte 4) ou restrito à LAN. Não há "tela de login" para proteger sozinho.
- **Arquivo `.fed`:** centraliza a configuração e fica junto das notas; as env vars da stack têm precedência para os segredos.
- **Imagens locais vs S3:** este guia usa a pasta local `/srv/frankmd/images`. O FrankMD também suporta upload para **AWS S3** (variáveis `AWS_*`) — adicione-as ao `environment:` se preferir hospedar as imagens num bucket.
- **Busca de imagens é gratuita:** o editor busca imagens na web via **DuckDuckGo** e **Pinterest** sem chave, além de gerar via IA (Gemini). A antiga aba **Google Images** ficou de fora porque o Google descontinuou o "Pesquisar em toda a Web" e encerra a Custom Search API em jan/2027 (sem substituto de busca na web inteira self-service).
- **Thruster + Puma:** dentro do container, o Thruster (padrão do Rails 8) escuta na `80` e faz proxy para o Puma; rodar como uid 1000 é esperado e o `no-new-privileges:true` não interfere no bind.

---

## Acessos

| Recurso              | URL / Local                 |
| :------------------- | :-------------------------- |
| **Web UI (público)** | `https://notas.exemplo.com` |
| **Local (LAN)**      | `http://IP_DO_HOST:7591`    |
| **Portainer**        | Stack `frankmd`             |
| **Notas (host)**     | `/srv/frankmd/notes`        |

---

## Referências

- [FrankMD — Repositório oficial (GitHub)](https://github.com/akitaonrails/FrankMD)
- [FrankMD — docker-compose.yml de referência](https://github.com/akitaonrails/FrankMD/blob/master/docker-compose.yml)
- [Google AI Studio — API keys (Gemini)](https://aistudio.google.com/app/apikey)
- [Google Cloud Console — APIs & Services](https://console.cloud.google.com/)
- [Google — Descontinuação do "Pesquisar em toda a Web" (Programmable Search)](https://support.google.com/programmable-search/answer/12397162)
- [Cloudflare Zero Trust — Access (apps self-hosted)](https://developers.cloudflare.com/cloudflare-one/applications/configure-apps/self-hosted-public-app/)
