# 📄 Stirling-PDF (Editor de PDF Self-Hosted via Docker + Cloudflare Tunnel)

Este guia sobe o **[Stirling-PDF](https://github.com/Stirling-Tools/Stirling-PDF)** — uma plataforma **open-source** de edição de PDF com **50+ ferramentas** (juntar, dividir, girar, comprimir, converter de/para Office e imagens, assinar, carimbar, adicionar/remover senha, **OCR**, redigir, reorganizar páginas, pipelines de automação, entre outras). Tudo roda no seu servidor, em **container único**, sem enviar seus arquivos para nuvem de terceiros. A stack usa **Docker**, idioma **pt-BR**, **login nativo** do Stirling, **OCR em português** e exposição via **Cloudflare Tunnel**, com todos os dados centralizados em **`/srv/pdf`**, no mesmo padrão dos outros guias do repo.

**Pré-requisito:** Docker Engine + Docker Compose instalados. Se ainda não tem, veja o guia [Docker + Portainer no Debian](./portainer-debian.md). Para o acesso externo, assume-se um `cloudflared` já rodando **bare metal no host** (você só adiciona o subdomínio pelo painel do Cloudflare One — ver [Parte 5](#parte-5-acesso-externo-via-cloudflare-tunnel)).

A stack pronta está em [`assets/stacks/stirling-pdf.yml`](../assets/stacks/stirling-pdf.yml).

> ℹ️ **Sem banco de dados externo.** O Stirling-PDF é um app **Spring Boot (Java)** que persiste tudo (configuração + banco de usuários SQLite) dentro de `/configs`. Não há Postgres/MariaDB para gerenciar — o backup é só copiar `/srv/pdf`.

## Arquitetura

```
┌─ INTERNET ──────────────────────────────────────────────────────────┐
│                                                                     │
│  Navegador                                                          │
│  ──► https://pdf.exemplo.com                                        │
│  ──► Cloudflare Edge (termina o TLS)                                │
│  ──► (opcional) Cloudflare Access — camada extra antes do app       │
│  ──► Tunnel (cloudflared bare metal no host)                        │
│  ──► localhost:8080 ──► Stirling-PDF (Spring Boot, HTTP puro)       │
│         │                                                           │
│         ├──► /srv/pdf/config    (settings + banco de usuários)      │
│         ├──► /srv/pdf/tessdata  (idiomas do OCR: eng + por + osd)   │
│         ├──► /srv/pdf/logs                                          │
│         └──► /srv/pdf/pipeline  (automações — opcional)             │
│                                                                     │
│  O login nativo do Stirling (admin + usuários) protege o app.       │
└─────────────────────────────────────────────────────────────────────┘
```

**Portas no host:**

| Porta Host | Porta Container | Uso                                                                              |
| :--------- | :-------------- | :------------------------------------------------------------------------------- |
| `8080/tcp` | `8080`          | Stirling-PDF — Web UI + API REST. Alvo do `cloudflared` e do acesso pela LAN.    |

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

O Stirling-PDF faz OCR com o **Tesseract**, que lê os idiomas de `/usr/share/tessdata`. Como a stack **monta `/srv/pdf/tessdata` por cima dessa pasta**, é preciso colocar ali os `.traineddata` que você quer — **incluindo o inglês** (`eng`), senão o bind mount "esconde" o idioma que já vinha na imagem e o OCR fica sem nenhum.

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

## Parte 3: (Opcional) Admin Inicial Forte

Por padrão, no 1º boot o Stirling cria o admin `admin` / `stirling` e você troca a senha no primeiro acesso ([Parte 6](#parte-6-primeiro-login-e-troca-de-senha)). Se preferir **já subir com um admin de senha forte**, descomente na stack as duas linhas de `SECURITY_INITIALLOGIN_*` e defina os valores como segredos nas **Environment variables** do Portainer:

| Variável                         | O que é                          | Exemplo / Como gerar          |
| :------------------------------- | :------------------------------- | :---------------------------- |
| `STIRLING_ADMIN_USER`            | Usuário admin inicial            | `gustavo`                     |
| `STIRLING_ADMIN_PASSWORD`        | Senha do admin inicial (forte)   | `openssl rand -base64 24`     |
| `STIRLING_UID` / `STIRLING_GID`  | UID/GID do host (default `1000`) | `id -u` / `id -g`             |

> ⚠️ As variáveis `SECURITY_INITIALLOGIN_*` só têm efeito **na primeira criação** do usuário (banco em `/configs` ainda vazio). Depois disso, gerencie usuários e senhas pela própria interface (**Admin → User Control**). **Nunca** deixe `SECURITY_INITIALLOGIN_PASSWORD` definida em branco.

## Parte 4: A Stack (Deploy)

O arquivo [`stirling-pdf.yml`](../assets/stacks/stirling-pdf.yml) define **um único serviço**: a imagem oficial `stirlingtools/stirling-pdf:latest`, expondo a porta `8080`, com login nativo ligado, locale `pt-BR` e `healthcheck` no endpoint `/api/v1/info/status`.

### Deploy via Portainer (Stack)

1. Acesse o Portainer → **Stacks** → **Add Stack**.
2. **Nome:** `stirling-pdf`.
3. Cole o conteúdo de [`assets/stacks/stirling-pdf.yml`](../assets/stacks/stirling-pdf.yml) no **Web editor**.
4. Na aba **Environment variables** (no Portainer **não** se usa arquivo `.env`), adicione **apenas se precisar**:
   - `STIRLING_UID` / `STIRLING_GID` — só se o seu usuário do host não for `1000`.
   - `STIRLING_ADMIN_USER` / `STIRLING_ADMIN_PASSWORD` — só se você descomentou o admin forte da [Parte 3](#parte-3-opcional-admin-inicial-forte).
5. Clique em **Deploy the stack**.

> ⚠️ **Confira que as pastas da [Parte 1](#parte-1-preparar-as-pastas-de-dados) e os idiomas da [Parte 2](#parte-2-baixar-os-idiomas-do-ocr-tessdata) já existem _antes_ do Deploy.** Sem isso o container reinicia por `EACCES` (permissão) ou fica sem OCR.

> 🐚 **Alternativa via SSH (sem Portainer):** com um `.env` (opcional) ao lado do compose, rode `docker compose -f stirling-pdf.yml up -d`.

> 🐘 **Escolhendo a variante da imagem:** a stack usa `:latest` (todas as features, com OCR). Para trocar, edite a linha `image:`:
> - `:latest-fat` → tudo + fontes/ferramentas extras (conversões de máxima qualidade; imagem grande).
> - `:latest-ultra-lite` → só operações básicas, **sem OCR/conversões pesadas** (hardware bem limitado).

## Parte 5: Acesso Externo via Cloudflare Tunnel

Como o `cloudflared` já roda **bare metal no host**, basta publicar um hostname novo — **a stack não leva sidecar de cloudflared** (convenção do repo).

1. No painel **Cloudflare One** (Zero Trust) → **Networks → Tunnels** → seu tunnel → aba **Public Hostname** → **Add a public hostname**:
   - **Subdomain/Domain:** `pdf.exemplo.com`
   - **Service:** `HTTP` → `localhost:8080` (ou `IP_DO_HOST:8080`)
2. O Cloudflare termina o TLS na borda; o container do Stirling roda **HTTP puro** internamente (não precisa de protocolo `https` em lugar nenhum da stack).

> 🔒 **Camada extra (opcional):** diferente de apps sem login, o Stirling **já tem autenticação própria**, então o Cloudflare Access não é obrigatório. Ainda assim, colocar uma **Application self-hosted** no Zero Trust (Access → Applications) na frente de `pdf.exemplo.com` adiciona uma camada de defesa (OTP por e-mail/SSO) antes mesmo de chegar à tela de login do Stirling.

## Parte 6: Primeiro Login e Troca de Senha

1. Acesse `https://pdf.exemplo.com` ou, na LAN, `http://IP_DO_HOST:8080`.
2. Faça login com o admin padrão (ou o definido na [Parte 3](#parte-3-opcional-admin-inicial-forte)):
   - **Usuário:** `admin`
   - **Senha:** `stirling`
3. **Troque a senha imediatamente:** menu do usuário (canto superior) → **Account Settings** → **Change Password**.
4. Crie usuários adicionais, se quiser, em **Admin → User Control**. A interface já vem em **português (pt-BR)** por causa de `SYSTEM_DEFAULTLOCALE=pt-BR`.
5. Teste o **OCR**: abra uma ferramenta de OCR, faça upload de um PDF escaneado e confirme que **Português** aparece na lista de idiomas (validando a [Parte 2](#parte-2-baixar-os-idiomas-do-ocr-tessdata)). 🚀

> ⚠️ Trocar a senha do admin no 1º acesso **não é opcional** — `admin`/`stirling` é público. Se expôs pelo túnel sem Cloudflare Access, faça isso antes de qualquer outra coisa.

## Parte 7: Atualização

A imagem usa a tag rolling `stirlingtools/stirling-pdf:latest`.

**Via Portainer (recomendado):**

1. Portainer → **Stacks** → `stirling-pdf`.
2. Clique em **Editor** (ou **Update the stack**) e marque **`Re-pull image and redeploy`**.
3. Clique em **Update the stack**. Sem marcar isso, o Redeploy comum **reusa o cache** e não baixa a imagem nova.

**Via SSH:**

```bash
docker compose -f stirling-pdf.yml pull
docker compose -f stirling-pdf.yml up -d
```

> 💾 Configuração, usuários e idiomas de OCR ficam nos bind mounts `/srv/pdf/*` (no host), então atualizar/recriar o container **não apaga** nada.

> 🔒 **Quer reprodutibilidade?** Fixe a versão na imagem (ex.: `stirlingtools/stirling-pdf:<tag>`) e, para atualizar, bump a tag — assim você sempre sabe qual versão está rodando.

## Parte 8: Backup

Todo o estado do Stirling-PDF é arquivo em `/srv/pdf` — o backup é um único `tar`:

```bash
# snapshot completo (config + banco de usuários + idiomas OCR + pipelines)
sudo tar czf stirling-pdf-backup-$(date +%F).tar.gz -C /srv pdf
```

> 💾 O diretório **crítico** é `/srv/pdf/config` (contém `settings.yml` e o banco de usuários SQLite). Guardá-lo já restaura logins, ferramentas e preferências. Os idiomas de OCR (`tessdata`) são recriáveis via [Parte 2](#parte-2-baixar-os-idiomas-do-ocr-tessdata) caso queira um backup mais enxuto.

---

## Troubleshooting

| Sintoma                                             | Causa provável / Correção                                                                                                                                          |
| :-------------------------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Container reinicia em loop / `EACCES` nos logs      | Pastas de `/srv/pdf` são de `root`. Pare a stack e rode `sudo chown -R 1000:1000 /srv/pdf` (Parte 1). Se o host não é uid 1000, defina `STIRLING_UID`/`STIRLING_GID`. |
| Container fica `unhealthy` logo após subir          | Normal nos primeiros ~60s (Java + LibreOffice bootam devagar). Só investigue se persistir; veja `docker logs stirling-pdf`.                                          |
| **OCR não lista Português** (ou nenhum idioma)      | O bind mount de `tessdata` está vazio/incompleto. Baixe `eng` + `por` + `osd` em `/srv/pdf/tessdata` e faça `chown 1000:1000` (Parte 2), depois redeploy.            |
| **502 / Bad Gateway** no domínio do túnel           | Public Hostname apontando para serviço/porta errados. Use `HTTP` → `localhost:8080` (Parte 5).                                                                       |
| Não consigo logar / esqueci a senha do admin        | Pare a stack, apague o banco de usuários em `/srv/pdf/config` (ou defina um novo admin via `SECURITY_INITIALLOGIN_*`) e suba de novo. **Faça backup antes.**         |
| Falha ao subir com `no-new-privileges` (permissão)  | Raro. Se o drop de privilégios falhar, remova temporariamente `security_opt: [no-new-privileges:true]` ou os `PUID/PGID` (roda como root) e reporte.                 |
| Conversão de Office (docx/xlsx) falha ou trava      | Depende do LibreOffice embutido (RAM). Dê mais memória ao container/host, ou use a imagem `:latest-fat` para o conjunto completo de fontes/ferramentas.              |
| Upload grande é rejeitado                            | Aumente `SYSTEM_MAXFILESIZE` (em MB) na stack e redeploy. Atenção também a limites do Cloudflare Tunnel para arquivos muito grandes.                                 |

---

## Notas Importantes

- **Sem banco de dados externo:** todo o estado (config + usuários SQLite) vive em `/srv/pdf/config`. Backup e portabilidade são triviais — copie a pasta.
- **Login nativo (segurança):** o app tem autenticação própria (`SECURITY_ENABLELOGIN=true`). O admin padrão `admin`/`stirling` **precisa** ter a senha trocada no 1º acesso (Parte 6). O Cloudflare Access é uma camada extra opcional (Parte 5).
- **OCR precisa dos idiomas montados:** por causa do bind mount em `/usr/share/tessdata`, os `.traineddata` (inclusive `eng`) têm de estar em `/srv/pdf/tessdata`. Sem eles, o OCR fica sem idiomas (Parte 2).
- **Consumo de recursos:** por ser Java + LibreOffice + Tesseract, o Stirling-PDF pede mais RAM que os apps leves do repo (folga de ~1–2 GB ajuda nas conversões). Em hardware bem limitado, considere `:latest-ultra-lite` (abre mão de OCR/conversões pesadas).
- **Variantes da imagem:** `:latest` (padrão, equilibrado, com OCR), `:latest-fat` (tudo + fontes/ferramentas extras), `:latest-ultra-lite` (mínimo). Trocar é só mudar a tag e redeploy.
- **Privacidade:** os arquivos são processados **localmente** no container e não saem para serviços externos — é o principal motivo de rodar self-hosted.
- **Pipelines:** o volume `/srv/pdf/pipeline` guarda automações (ex.: OCR → comprimir → carimbar em lote) criadas pela própria UI, sem código.

---

## Acessos

| Recurso               | URL / Local                |
| :-------------------- | :------------------------- |
| **Web UI (público)**  | `https://pdf.exemplo.com`  |
| **Local (LAN)**       | `http://IP_DO_HOST:8080`   |
| **Portainer**         | Stack `stirling-pdf`       |
| **Dados (host)**      | `/srv/pdf`                 |
| **Config crítica**    | `/srv/pdf/config`          |

---

## Referências

- [Stirling-PDF — Repositório oficial (GitHub)](https://github.com/Stirling-Tools/Stirling-PDF)
- [Stirling-PDF — Documentação](https://docs.stirlingpdf.com)
- [Stirling-PDF — Instalação com Docker](https://docs.stirlingpdf.com/Installation/Docker%20Install)
- [tesseract-ocr/tessdata_fast — Idiomas de OCR](https://github.com/tesseract-ocr/tessdata_fast)
- [Cloudflare Zero Trust — Access (apps self-hosted)](https://developers.cloudflare.com/cloudflare-one/applications/configure-apps/self-hosted-public-app/)
