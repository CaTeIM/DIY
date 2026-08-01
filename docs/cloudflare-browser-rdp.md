# 🖥️ RDP no Navegador (Cloudflare Access + Tunnel)

Acessar a área de trabalho de um **PC de casa** a partir de uma **máquina corporativa gerenciada**, usando
**apenas o navegador**. Sem instalar VPN, sem cliente RDP, sem extensão e sem WARP no lado de quem acessa.
O recurso é o **Browser-based RDP** da Cloudflare (GA desde 22/09/2025), que roda no plano **Zero Trust Free**.

> 🎯 **Problema que este guia resolve:** redes corporativas costumam bloquear ferramentas de acesso remoto
> por **categoria de domínio**. No caso real que originou este guia, o proxy Squid da empresa devolvia
> `ERR_DNS_FAIL` para **qualquer domínio contendo "tailscale"**, enquanto `github.com` e `cloudflare.com`
> passavam normalmente. A saída foi parar de tentar furar o bloqueio com VPN e usar o que **já é permitido**:
> uma URL HTTPS num **domínio próprio**, aberta no navegador.

**Pré-requisito:** um domínio ativo na Cloudflare e uma organização Zero Trust (team domain
`<seu-time>.cloudflareaccess.com`). O PC alvo precisa ser **Windows Pro** ou superior (o Home não hospeda RDP).

## Arquitetura

```
  PC da empresa (só navegador)                            PC de casa (Windows Pro)
  ┌──────────────────────────────┐                        ┌────────────────────────────────┐
  │ Navegador                    │                        │  cloudflared (serviço)         │
  │ https://remote.seudominio... │──── HTTPS/WSS 443 ───► │        │                       │
  │   login no Access + MFA      │   (via proxy da        │        │ loopback              │
  │   sessão RDP renderizada     │    empresa, normal)    │        ▼                       │
  └──────────────────────────────┘                        │  RDP em 127.0.0.1:3389         │
                                                          │  (3389 bloqueada p/ a rede)    │
        Túnel outbound-only. Nenhuma porta aberta         └────────────────────────────────┘
        na internet residencial. Nada com "vpn" no nome.
```

O `cloudflared` roda **no PC de casa** e cria uma conexão **de dentro para fora**. Quem acessa só enxerga
`https://remote.seudominio.com`, que para o filtro corporativo é um site qualquer. O RDP trafega encapsulado
em **WebSocket sobre TLS** na porta 443.

> ℹ️ **Por que isso passa onde a VPN não passa:** nenhum domínio do fluxo carrega palavra que caia em lista de
> bloqueio de VPN/proxy. O domínio da sessão é **seu**, e o login usa `*.cloudflareaccess.com`, que costuma ser
> categorizado como serviço de negócio. Antes de investir no setup, **teste** (ver [Parte 1](#parte-1-teste-de-viabilidade-faça-isto-primeiro)).

## Parte 1: Teste de viabilidade (faça isto primeiro)

Não monte nada antes deste teste. No navegador da **máquina corporativa**, abra:

```
https://<seu-time>.cloudflareaccess.com
```

- **Carregou a página de login do Cloudflare Access?** ✅ Siga o guia.
- **Deu erro de DNS ou página de bloqueio?** ❌ O proxy bloqueia o domínio de login e este caminho não serve.

Para diagnosticar um bloqueio com precisão (distinguir sinkhole de DNS, bloqueio por IP, inspeção TLS e proxy
autenticado), o script [`assets/scripts/diag-proxy-corporativo.ps1`](../assets/scripts/diag-proxy-corporativo.ps1)
testa as quatro camadas e emite um veredito. Rode com:

```powershell
pwsh -ExecutionPolicy Bypass -File .\diag-proxy-corporativo.ps1 > diag.txt 2>&1
```

> ⚠️ Se a máquina corporativa exige **proxy autenticado** (HTTP 407), o instalador do Cloudflare pode falhar ao
> baixar pacotes. Baixe o MSI numa rede livre e leve por pendrive, conferindo o hash antes de instalar.

## Parte 2: Preparar o RDP no PC de casa

Tudo em **PowerShell como administrador**, na máquina que será acessada.

**1. Senha forte.** Contas sem senha são bloqueadas para logon remoto pelo Windows. Defina uma senha na conta
que fará o acesso, ou crie uma conta dedicada (mais seguro, evita usar a conta principal do dia a dia):

```powershell
# opção A: senha na conta existente
net user <usuario> *

# opção B (recomendada): conta dedicada, sem privilégio de admin
$p = Read-Host -AsSecureString "Senha forte para o usuario RDP"
New-LocalUser -Name 'rdpuser' -Password $p -FullName 'Acesso Remoto'
Add-LocalGroupMember -SID 'S-1-5-32-555' -Member 'rdpuser'   # grupo Área de Trabalho Remota
```

**2. Habilitar o RDP e exigir NLA:**

```powershell
Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name UserAuthentication -Value 1
```

**3. Conferir a camada de segurança.** O Browser-based RDP **exige TLS**. O valor precisa ser `1` (Negotiate)
ou `2` (SSL). Se vier `0` (RDP legado), não funciona:

```powershell
(Get-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name SecurityLayer).SecurityLayer
```

**4. Fechar a 3389 para a rede.** Como o `cloudflared` roda na própria máquina e fala por **loopback**
(que o Windows Firewall não filtra), dá para bloquear a porta para todo o resto. É a menor superfície de ataque:

```powershell
Disable-NetFirewallRule -DisplayGroup 'Área de Trabalho Remota' -ErrorAction SilentlyContinue
Disable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName 'Block RDP 3389 inbound (rede)' -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Block -Profile Any
```

**5. Reiniciar a máquina.** O `TermService` é _trigger-started_ e só cria o listener da 3389 no boot. Habilitar
o RDP com o serviço já rodando **não** sobe a porta, e `Restart-Service TermService` costuma falhar com
"stop failed". Reinicie e confirme:

```powershell
Get-NetTCPConnection -State Listen -LocalPort 3389
```

**6. Fixar o IP.** Faça **reserva de DHCP** no roteador para essa máquina. O alvo na Cloudflare aponta para um
IP fixo; se ele mudar, o acesso quebra.

> ⚠️ **VPN de túnel completo na máquina alvo** (Mullvad, ProtonVPN, etc.) quebra o acesso: o `cloudflared`
> roda como SYSTEM e recebe `WSA 10065 no route to host` ao tentar alcançar o IP da LAN. Ligue a opção de
> **compartilhamento de rede local** da VPN, ou desconecte-a nessa máquina.

## Parte 3: Túnel e rota na Cloudflare

1. **Túnel:** painel Cloudflare → **Networking** → **Tunnels** → crie um túnel (ou reutilize um existente) e
   rode o comando exibido para o Windows na máquina de casa:
   ```powershell
   cloudflared.exe service install <TOKEN>
   ```
   Confirme que o conector aparece como **Connected**.
2. **Rota CIDR:** **Networking** → **Routes** → **Create route** → **Tunnel CIDR**. Informe o IP do PC com
   máscara `/32` (ex.: `192.168.1.50/32`) e selecione o túnel.

> ℹ️ O aviso do painel sobre "Cloudflare One Client" nessa tela **não se aplica** aqui: no Browser-based RDP o
> próprio navegador é o ponto de entrada, então o WARP não é necessário.

## Parte 4: Target

**Zero Trust** → **Access controls** → **Targets** → **Add a target**:

| Campo           | Valor                                                          |
| :-------------- | :------------------------------------------------------------- |
| Target hostname | nome amigável (ex.: `pc-casa`)                                 |
| IP addresses    | o IP do PC (ex.: `192.168.1.50`), na virtual network `default` |

> ℹ️ O _target hostname_ é só um rótulo para políticas e logs. **Não** é um endereço DNS e não se confunde com
> o `remote.seudominio.com`. Se o IP não aparecer no dropdown, a rota da Parte 3 não foi criada.

## Parte 5: Registro DNS

No dashboard **da zona** (não no Zero Trust): **DNS** → **Records** → **Add record**:

| Campo        | Valor                       |
| :----------- | :-------------------------- |
| Type         | `A`                         |
| Name         | `remote`                    |
| IPv4 address | `240.0.0.0`                 |
| Proxy status | **Proxied** (nuvem laranja) |

> ℹ️ O `240.0.0.0` é um endereço **fantasma** de propósito (faixa Classe E, não roteável). Quem faz o
> roteamento real é o proxy da Cloudflare. O registro só precisa existir e estar **proxied**.

## Parte 6: Access Application

**Zero Trust** → **Access controls** → **Applications** → **Create new application**:

1. **Self-hosted and private** → **Add public hostname**.
2. **Domain:** subdomínio `remote` + o seu domínio.
3. Ligue **"Allow access through browser-based RDP, SSH, or VNC sessions"** e escolha **RDP**.
4. **Target criteria:** selecione o target da Parte 4. **Port:** `3389`.
5. **Authentication → Identity:** deixe **"Accept all available identity providers"** ligado, ou marque o
   método desejado (`onetimepin` envia um código por e-mail; o IdP `Cloudflare` usa a sua própria conta).
6. **Access policies:** crie uma regra e **salve com `Save policy`**:

| Campo       | Valor                              |
| :---------- | :--------------------------------- |
| Policy name | `RDP Casa`                         |
| Action      | **Allow**                          |
| Include     | `Emails` → o seu e-mail específico |

7. **MFA (opcional):** na política ou na aba **MFA**, exija segundo fator (TOTP, chave de segurança,
   biometria). No primeiro login o Cloudflare pede o cadastro do autenticador.

> ⚠️ **Antes de salvar**, confira o bloco **Preview**: os três campos precisam estar preenchidos. Se aparecer
> "No sources set", "No policies added" ou "No destinations assigned", alguma seção não foi gravada. O erro
> mais comum é montar a política no Builder e esquecer do botão **`Save policy`**.

> ℹ️ **Bypass** e **Service Auth** não são suportados em aplicações com browser rendering: só **Allow** e
> **Block**. Isso é bom, garante que ninguém chega ao RDP sem autenticar.

## Parte 7: (Opcional) Política de rede no Gateway

**Zero Trust** → **Traffic policies** → **Firewall policies** → aba **Network** → **Add a policy**:

| Selector                     | Operator | Value     | Action    |
| :--------------------------- | :------- | :-------- | :-------- |
| Access Infrastructure Target | is       | `Present` | **Allow** |

> ℹ️ **Isto é opcional e fica dormente** se o proxy do Gateway estiver desligado (o painel avisa: _"Policies
> will not take effect until the Proxy switch is turned on"_). Ela **não** é o que faz o RDP funcionar. Serve
> como rede de proteção para quem já tem outras network policies, especialmente alguma de **Block** que
> pudesse pegar RDP/SSH antes. **Não ligue o proxy do Gateway só por causa dela.**

## Parte 8: Uso no dia a dia

Na máquina corporativa, só com o navegador:

1. Abra `https://<seu-time>.cloudflareaccess.com`, autentique e clique no tile do PC. A URL direta também
   funciona: `https://remote.seudominio.com/rdp/<vnet-id>/<ip-do-target>/3389`.
2. Na tela **"Sign in to your remote desktop"**, informe **usuário e senha do Windows** do PC de casa. Se o
   usuário sozinho não for aceito, tente `.\usuario`.

> ℹ️ **A sessão é a sua, não uma nova.** O Windows Pro é sessão única por usuário: conectando com a mesma conta
> já logada, o RDP **assume a sessão do console**, com todos os programas e janelas abertos. A tela física
> trava enquanto você acessa (privacidade), e volta ao normal quando alguém desbloqueia lá. Fechar a aba
> apenas desconecta e mantém tudo rodando; só o **logoff** encerra a sessão de verdade.

## Troubleshooting

| Sintoma                                                   | Causa provável                                                    | Correção                                                                       |
| :-------------------------------------------------------- | :---------------------------------------------------------------- | :----------------------------------------------------------------------------- |
| `Code 4: Host unreachable` / `WSA 10065 no route to host` | VPN de túnel completo na máquina alvo desviando a rota da LAN     | Ligue o compartilhamento de rede local na VPN, ou desconecte-a                 |
| Erro de conexão e a 3389 não escuta                       | listener não subiu; RDP habilitado com o serviço já rodando       | **Reinicie a máquina** (`Restart-Service TermService` falha com "stop failed") |
| `Connection refused` ao testar a 3389 local               | serviço parado ou RDP desabilitado                                | Confira `fDenyTSConnections = 0` e reinicie                                    |
| Login OK mas a tela não renderiza / congela               | proxy corporativo cortando o WebSocket                            | Peça liberação de upgrade WebSocket para o seu domínio                         |
| Preview da aplicação com "No policies added"              | política montada no Builder mas não salva                         | Clique em **`Save policy`**                                                    |
| IP não aparece no dropdown do Target                      | rota CIDR ausente                                                 | Crie a rota em **Networking → Routes** (Parte 3)                               |
| Instalador falha com `0x80070003`                         | bootstrapper sem acesso ao repositório de pacotes (404 do filtro) | Baixe o MSI completo noutra rede e instale com `msiexec /i`                    |
| Sessão exige senha e ela não é aceita                     | conta sem senha ou senha em branco                                | Windows bloqueia logon remoto com senha em branco; defina uma senha real       |

## Notas Importantes

- **Nada exposto na internet:** o túnel é _outbound-only_. Nenhuma porta é aberta no roteador de casa, e a
  3389 fica bloqueada até para a LAN.
- **Autenticação em duas camadas:** primeiro o Cloudflare Access (com MFA), depois as credenciais do Windows.
  A Cloudflare **não** gerencia a senha do Windows.
- **Só navegador do outro lado:** nenhuma instalação na máquina corporativa. Chrome, Edge, Firefox e Safari
  são suportados; IE11 não.
- **Limitações do recurso:** sem áudio, clipboard limitado a **500 KB** e somente texto, transferência de
  arquivos em **beta**, impressão apenas em PDF.
- **Custo:** incluído no **Zero Trust Free** (até 50 assentos), sem cobrança por sessão. Confirme a página de
  planos antes de contar com isso a longo prazo.
- **Windows Home não serve** como alvo: não hospeda RDP. Nesse caso o caminho é VNC no navegador (mesmo
  toggle da aplicação), com um servidor VNC instalado.
- **Uso consciente:** contornar controles de rede da sua empresa pode violar a política de uso aceitável do
  empregador. Verifique se você tem autorização antes de aplicar isto num equipamento corporativo.

## Acessos

| O quê                   | Onde                                                       | Proteção                                     |
| :---------------------- | :--------------------------------------------------------- | :------------------------------------------- |
| Sessão RDP no navegador | `https://remote.seudominio.com/rdp/<vnet-id>/<ip>/3389`    | Cloudflare Access + MFA + credencial Windows |
| App Launcher            | `https://<seu-time>.cloudflareaccess.com`                  | Cloudflare Access + MFA                      |
| Painel Zero Trust       | [one.dash.cloudflare.com](https://one.dash.cloudflare.com) | conta Cloudflare                             |

## Referências

- [Cloudflare: Connect to RDP in a browser](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/use-cases/rdp/rdp-browser/)
- [Cloudflare: Browser-based RDP GA (22/09/2025)](https://developers.cloudflare.com/changelog/post/2025-09-22-browser-based-rdp-ga/)
- [Cloudflare: Network policies](https://developers.cloudflare.com/cloudflare-one/traffic-policies/network-policies/)
- [Microsoft: Enable Remote Desktop](https://learn.microsoft.com/windows-server/remote/remote-desktop-services/clients/remote-desktop-allow-access)
- [Tailscale (este repo)](./tailscale.md) · [RustDesk Headless (este repo)](./rustdesk-headless.md)
