# 📄 Stirling-PDF (Editor de PDF Self-Hosted atrás do Authelia)

Este guia sobe o **[Stirling-PDF](https://github.com/Stirling-Tools/Stirling-PDF)** — uma plataforma **open-source** de edição de PDF com **50+ ferramentas** (juntar, dividir, girar, comprimir, converter de/para Office e imagens, assinar, carimbar, adicionar/remover senha, **OCR**, redigir, reorganizar páginas, pipelines de automação, entre outras). Tudo roda no seu servidor, em **container único**, sem enviar seus arquivos para nuvem de terceiros.

Diferente de um deploy solto, aqui a **autenticação é delegada ao [Authelia + lldap](./authelia.md)** por trás do **[Caddy](./caddy.md)**: o **login nativo do Stirling fica desligado** (assim o app fica **aberto e SEM o limite de 5 usuários** do plano free), o container entra na rede `caddy-net` **sem publicar porta no host**, e o acesso externo é via **Cloudflare Tunnel**. Todos os dados ficam em **`/srv/pdf`**, no mesmo padrão dos outros guias do repo.

**Pré-requisito:** Docker + Portainer ([./portainer-debian.md](./portainer-debian.md)) **e** as stacks **[authelia](./authelia.md)** e **[caddy](./caddy.md)** já no ar — são elas que fazem o login.

A stack pronta está em [`assets/stacks/stirling-pdf.yml`](../assets/stacks/stirling-pdf.yml).

> [!IMPORTANT]
> **Login nativo desligado pela dupla oficial da v2.** A stack usa a **imagem oficial completa**
> (`stirlingtools/stirling-pdf:latest-fat`) com `SECURITY_ENABLELOGIN=false` **+**
> `DISABLE_ADDITIONAL_FEATURES=false` (esta segunda é o que faz o `enableLogin` valer). Assim o app
> fica **aberto** — sem tela de login própria, sem banco de usuários, sem o teto de 5 — e quem
> autentica é o **Authelia**. A tela de configurações fica **escondida** (`SYSTEM_SHOWSETTINGSWHENNOLOGIN=false`);
> você administra pelo `settings.yml`/Portainer no host.
>
> > ⚠️ **v1→v2 (aprendido em produção):** **NÃO** use `DISABLE_ADDITIONAL_FEATURES=true` para "abrir"
> > o app. Na **v2.14.0** essa flag só desativa o grupo `enterprise`; o **login continua ATIVO** (cria
> > `admin` + banco de usuários + trava de 5) e o SPA chama `/login` e `/api/v1/auth/me` — resultado:
> > **login duplo** com o Authelia. O jeito certo é a dupla acima (doc oficial → _Running Without
> > Authentication_, Opção 1).

> ℹ️ **Sem banco de dados externo.** O Stirling-PDF é um app **Spring Boot (Java)** que persiste a
> configuração dentro de `/configs`. Com o login desligado **não há banco de usuários** para
> gerenciar — o backup é só copiar `/srv/pdf`.

## Arquitetura

```
Navegador ──► https://pdf.selflabs.org
   └─► Cloudflare (termina o TLS) ──► cloudflared (bare metal no host) ──► Caddy :8080
        │
        ├─► forward-auth ──► Authelia (login + 2FA)      ◄── rede auth-net
        └─► (autorizado) ──► Stirling-PDF :8080          ◄── rede caddy-net (SEM porta no host)
               ├─► /srv/pdf/config    (settings; SEM banco de usuários)
               ├─► /srv/pdf/tessdata  (idiomas do OCR: eng + por + osd)
               ├─► /srv/pdf/logs
               └─► /srv/pdf/pipeline  (automações — opcional)

Quem autentica é o Authelia; o Stirling roda ABERTO por trás dele.
```

**Portas no host:** o Stirling **não publica porta** — só `expose: 8080` na rede `caddy-net`. Quem publica (preso a `127.0.0.1:8080`, para o `cloudflared`) é o **Caddy**. Isso significa que o app **só** é alcançável depois de passar pelo Authelia.

> A imagem sobe como `root` e **dropa privilégios** para o `PUID:PGID` da stack (padrão `1000:1000`) — por isso as pastas em `/srv/pdf` precisam ser desse usuário (ver [Parte 1](#parte-1-preparar-as-pastas-de-dados)).

---

## Parte 1: Preparar as Pastas de Dados

Seguindo o padrão `/srv`, crie as pastas onde o Stirling-PDF vai persistir configuração, idiomas de OCR, logs e pipelines.

```bash
sudo mkdir -p /srv/pdf/config /srv/pdf/tessdata /srv/pdf/logs /srv/pdf/pipeline

# o container dropa privilégios para o UID/GID 1000 (padrão da stack);
# as pastas precisam ser dele, senão dá EACCES ao gravar config/logs
sudo chown -R 1000:1000 /srv/pdf
```

> ⚠️ **Crie as pastas _antes_ do Deploy.** Se o Portainer subir primeiro, o Docker cria `/srv/pdf/*` como `root` e o Stirling (uid 1000) não consegue gravar (`EACCES`, container reiniciando).

> ℹ️ **UID/GID diferente de 1000?** Descubra com `id -u` / `id -g`, ajuste o `chown` acima e defina `STIRLING_UID`/`STIRLING_GID` nas env vars do Portainer (a stack usa `1000` por padrão).

## Parte 2: Baixar os Idiomas do OCR (tessdata)

O Stirling-PDF faz OCR com o **Tesseract**, que lê os idiomas de **`/usr/share/tesseract-ocr/5/tessdata`**. Como a stack **monta `/srv/pdf/tessdata` por cima dessa pasta**, é preciso colocar ali os `.traineddata` que você quer — **incluindo o inglês** (`eng`), senão o bind mount "esconde" o idioma que já vinha na imagem e o OCR fica sem nenhum.

Baixe **inglês + português + OSD** (detecção de orientação) do repositório oficial `tessdata_fast` (versão leve, ideal para ARM/SBC):

```bash
cd /srv/pdf/tessdata

sudo curl -fLO https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/main/eng.traineddata
sudo curl -fLO https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/main/por.traineddata
sudo curl -fLO https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/main/osd.traineddata

# garanta que os arquivos pertencem ao usuário do container
sudo chown 1000:1000 /srv/pdf/tessdata/*.traineddata
```

> 💡 **Quer mais idiomas?** É só baixar o `<código>.traineddata` correspondente (ex.: `spa` para espanhol, `deu` para alemão) na mesma pasta. A lista completa está em [tesseract-ocr/tessdata_fast](https://github.com/tesseract-ocr/tessdata_fast). Para máxima precisão (mais pesado), use o `tessdata_best`.

> ℹ️ Usando a imagem **`latest-ultra-lite`**? Ela **não traz OCR** — pode pular esta parte e remover o volume `tessdata` da stack.

## Parte 3: A Stack (Deploy)

O arquivo [`stirling-pdf.yml`](../assets/stacks/stirling-pdf.yml) define **um único serviço**: a imagem oficial `stirlingtools/stirling-pdf:latest-fat`, com **login desligado** (a dupla `SECURITY_ENABLELOGIN=false` + `DISABLE_ADDITIONAL_FEATURES=false`), locale `pt-BR`, `expose: 8080` na rede externa `caddy-net` (**sem porta no host**) e `healthcheck` no endpoint `/api/v1/info/status`.

### Deploy via Portainer (Stack)

1. Acesse o Portainer → **Stacks** → **Add Stack**.
2. **Nome:** `stirling-pdf`.
3. Cole o conteúdo de [`assets/stacks/stirling-pdf.yml`](../assets/stacks/stirling-pdf.yml) no **Web editor** (ou aponte para o repositório Git).
4. Na aba **Environment variables** (no Portainer **não** se usa arquivo `.env`), adicione **apenas se precisar**:
   - `STIRLING_UID` / `STIRLING_GID` — só se o seu usuário do host não for `1000`.
5. Clique em **Deploy the stack**.

> ⚠️ **Confira que as pastas da [Parte 1](#parte-1-preparar-as-pastas-de-dados) e os idiomas da [Parte 2](#parte-2-baixar-os-idiomas-do-ocr-tessdata) já existem _antes_ do Deploy.** Sem isso o container reinicia por `EACCES` (permissão) ou fica sem OCR.

> ⚠️ **A rede `caddy-net` precisa existir** (`docker network create caddy-net`) — ela é criada junto com a stack **[caddy](./caddy.md)**. Sem ela o deploy falha com `network caddy-net not found`.

> 🐚 **Alternativa via SSH (sem Portainer):** com um `.env` (opcional) ao lado do compose, rode `docker compose -f stirling-pdf.yml up -d`.

> 🐘 **Escolhendo a variante da imagem:** a stack usa `:latest-fat` (tudo + fontes/ferramentas extras, com OCR). Para trocar, edite a linha `image:`:
>
> - `:latest` → equilibrado, com OCR.
> - `:latest-ultra-lite` → só operações básicas, **sem OCR/conversões pesadas** (hardware bem limitado).

## Parte 4: Autenticação (Authelia) e exposição externa

O Stirling **não tem login próprio** aqui — quem barra o acesso é o **[Authelia](./authelia.md)**, e o roteamento é do **[Caddy](./caddy.md)**. As duas stacks já trazem tudo pronto:

- No **[Caddyfile](../assets/configs/caddy-Caddyfile)** já existe o bloco de `pdf.selflabs.org` com `import authelia` + `reverse_proxy stirling-pdf:8080`.
- No **[Authelia](../assets/configs/authelia.yml)** já existe a regra `pdf.selflabs.org` no `access_control` (por padrão `one_factor` = só senha; troque para `two_factor` se quiser exigir TOTP também).

**No `cloudflared`** (bare metal no host), publique o hostname apontando para o **Caddy**, não para o Stirling:

1. Painel **Cloudflare One** (Zero Trust) → **Networks → Tunnels** → seu tunnel → **Public Hostname** → **Add**:
   - **Subdomain/Domain:** `pdf.selflabs.org`
   - **Service:** `HTTP` → `localhost:8080` **(o Caddy)**
2. O Cloudflare termina o TLS na borda; Caddy e Stirling falam **HTTP puro** internamente.

> 🔒 O Cloudflare Access **não** é necessário: quem autentica é o Authelia (self-hosted). Túnel para expor, Authelia para logar.

## Parte 5: Primeiro Acesso e Gestão de Usuários

1. Abra `https://pdf.selflabs.org`. Sem sessão, o Authelia redireciona para o portal `auth.selflabs.org`.
2. Faça login com um **usuário do lldap** (criado na UI `users.selflabs.org` — ver [authelia.md → Bootstrap](./authelia.md#parte-4-bootstrap--criar-o-bind-do-authelia-e-seu-usuário)). No sucesso, você cai **direto na ferramenta do Stirling**, sem segunda tela de login.
3. **Criar/remover usuários** é no **lldap** (`users.selflabs.org`), não no Stirling. Um login cobre todos os `*.selflabs.org` (SSO).
4. Teste o **OCR**: abra uma ferramenta de OCR, faça upload de um PDF escaneado e confirme que **Português** aparece na lista de idiomas (validando a [Parte 2](#parte-2-baixar-os-idiomas-do-ocr-tessdata)). 🚀

> ℹ️ A interface já vem em **português (pt-BR)** por causa de `SYSTEM_DEFAULTLOCALE=pt-BR`.

## Parte 6: Atualização

A imagem usa a tag rolling `stirlingtools/stirling-pdf:latest-fat`.

**Via Portainer (recomendado):**

1. Portainer → **Stacks** → `stirling-pdf`.
2. Clique em **Editor** (ou **Update the stack**) e marque **`Re-pull image and redeploy`**.
3. Clique em **Update the stack**. Sem marcar isso, o Redeploy comum **reusa o cache** e não baixa a imagem nova.

**Via SSH:**

```bash
docker compose -f stirling-pdf.yml pull
docker compose -f stirling-pdf.yml up -d
```

> 💾 Configuração e idiomas de OCR ficam nos bind mounts `/srv/pdf/*` (no host), então atualizar/recriar o container **não apaga** nada.

> 🔒 **Quer reprodutibilidade?** Fixe a versão na imagem (ex.: `stirlingtools/stirling-pdf:<tag>`) e, para atualizar, bump a tag — assim você sempre sabe qual versão está rodando.

## Parte 7: Backup

Todo o estado do Stirling-PDF é arquivo em `/srv/pdf` — o backup é um único `tar`:

```bash
# snapshot completo (config + idiomas OCR + pipelines)
sudo tar czf stirling-pdf-backup-$(date +%F).tar.gz -C /srv pdf
```

> 💾 O diretório **crítico** é `/srv/pdf/config` (contém o `settings.yml` e preferências). Os idiomas de OCR (`tessdata`) são recriáveis via [Parte 2](#parte-2-baixar-os-idiomas-do-ocr-tessdata) caso queira um backup mais enxuto.

---

## Troubleshooting

| Sintoma                                             | Causa provável / Correção                                                                                                                                                                                                                       |
| :-------------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Tela de login do Stirling** aparece (login duplo) | O login nativo não foi desligado. Confirme `SECURITY_ENABLELOGIN=false` **e** `DISABLE_ADDITIONAL_FEATURES=false` (a dupla — só `DISABLE_...=true` **não** basta na v2). Recrie o container e, se quiser zerar, apague `/srv/pdf/config` antes. |
| Container reinicia em loop / `EACCES` nos logs      | Pastas de `/srv/pdf` são de `root`. Pare a stack e rode `sudo chown -R 1000:1000 /srv/pdf` (Parte 1). Se o host não é uid 1000, defina `STIRLING_UID`/`STIRLING_GID`.                                                                           |
| Container fica `unhealthy` logo após subir          | Normal nos primeiros ~60s (Java + LibreOffice bootam devagar). Só investigue se persistir; veja `docker logs stirling-pdf`.                                                                                                                     |
| **OCR não lista Português** (ou nenhum idioma)      | O bind mount de `tessdata` está vazio/incompleto. Baixe `eng` + `por` + `osd` em `/srv/pdf/tessdata` e faça `chown 1000:1000` (Parte 2), depois redeploy.                                                                                       |
| **502 / Bad Gateway** em `pdf.selflabs.org`         | App fora da `caddy-net`, nome de container errado no Caddyfile, ou o Authelia caído. Confirme que o `stirling-pdf` está na `caddy-net` e que o `authelia` está `Up`.                                                                            |
| Redireciona pro `auth.` e não volta                 | Problema no forward-auth/`X-Forwarded-Proto`. Ver [caddy → Troubleshooting](./caddy.md#troubleshooting).                                                                                                                                        |
| Conversão de Office (docx/xlsx) falha ou trava      | Depende do LibreOffice embutido (RAM). Dê mais memória ao container/host; a `:latest-fat` já traz o conjunto completo de fontes/ferramentas.                                                                                                    |
| Upload grande é rejeitado                           | Aumente `SYSTEM_FILEUPLOADLIMIT` (em MB) na stack e redeploy. Atenção também a limites do Cloudflare Tunnel para arquivos muito grandes.                                                                                                        |

---

## Notas Importantes

- **Autenticação externa:** o Stirling roda **aberto** (`SECURITY_ENABLELOGIN=false` + `DISABLE_ADDITIONAL_FEATURES=false`); quem protege é o **[Authelia](./authelia.md)** no forward-auth do **[Caddy](./caddy.md)**. Como o container **não publica porta**, ele só é alcançável depois do login. Nunca exponha a porta `8080` do Stirling direto no host.
- **Sem banco de usuários:** com o login off, não há contas nem limite de 5 usuários no Stirling — a identidade é toda do lldap. Todo o estado (config) vive em `/srv/pdf/config`.
- **OCR precisa dos idiomas montados:** por causa do bind mount em `/usr/share/tesseract-ocr/5/tessdata`, os `.traineddata` (inclusive `eng`) têm de estar em `/srv/pdf/tessdata`. Sem eles, o OCR fica sem idiomas (Parte 2).
- **Consumo de recursos:** por ser Java + LibreOffice + Tesseract, o Stirling-PDF pede mais RAM que os apps leves do repo (folga de ~1–2 GB ajuda nas conversões). Em hardware bem limitado, considere `:latest-ultra-lite` (abre mão de OCR/conversões pesadas).
- **Variantes da imagem:** `:latest` (equilibrado, com OCR), `:latest-fat` (tudo + fontes/ferramentas extras — o padrão desta stack), `:latest-ultra-lite` (mínimo). Trocar é só mudar a tag e redeploy.
- **Privacidade:** os arquivos são processados **localmente** no container e não saem para serviços externos — é o principal motivo de rodar self-hosted.
- **Pipelines:** o volume `/srv/pdf/pipeline` guarda automações (ex.: OCR → comprimir → carimbar em lote) criadas pela própria UI, sem código.

---

## Acessos

| Recurso                | URL / Local                               |
| :--------------------- | :---------------------------------------- |
| **Web UI (público)**   | `https://pdf.selflabs.org` (via Authelia) |
| **Gestão de usuários** | `https://users.selflabs.org` (lldap)      |
| **Portal de login**    | `https://auth.selflabs.org` (Authelia)    |
| **Portainer**          | Stack `stirling-pdf`                      |
| **Dados (host)**       | `/srv/pdf`                                |
| **Config crítica**     | `/srv/pdf/config`                         |

---

## Referências

- [Stirling-PDF — Repositório oficial (GitHub)](https://github.com/Stirling-Tools/Stirling-PDF)
- [Stirling-PDF — Documentação](https://docs.stirlingpdf.com)
- [Stirling-PDF — Running Without Authentication](https://docs.stirlingpdf.com/Configuration/System%20and%20Security)
- [tesseract-ocr/tessdata_fast — Idiomas de OCR](https://github.com/tesseract-ocr/tessdata_fast)
- [Authelia + lldap (este repo)](./authelia.md) · [Caddy (este repo)](./caddy.md)
