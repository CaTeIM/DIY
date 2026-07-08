# ☁️ Oracle Cloud Free Tier VPS (ARM) via Pay-As-You-Go

A Oracle oferece uma excelente VPS gratuita (Ampere A1 ARM com 4 OCPUs, 24GB de RAM e 200GB de disco), mas contas "Always Free" comuns quase nunca conseguem criar a máquina devido ao erro de falta de estoque (`Out of host capacity`).

O segredo para ignorar essa restrição é fazer o upgrade da conta para **Pay-As-You-Go (PAYG)**. Contas pagas ganham prioridade máxima na alocação de hardware. Desde que você configure a máquina **estritamente dentro dos limites gratuitos**, você terá prioridade total e a cobrança será **zero**.

## 🛠️ Passo 0: Criar a VCN Principal (Rede Virtual)

Antes de criar a máquina, você precisa de uma rede configurada com acesso à internet. A forma mais rápida e limpa é usar o Assistente:

1. No menu lateral principal, vá em **Networking** (Rede) > **Virtual Cloud Networks**.
2. Clique no botão **Start VCN Wizard** (Iniciar Assistente de VCN).
3. Selecione a opção **VCN with Internet Connectivity** (VCN com Conetividade à Internet) e clique no botão inferior **Start VCN Wizard**.
4. No campo **VCN Name**, digite exatamente `vcn-principal`.
5. Deixe todos os blocos de IP (CIDR) padrão e as configurações do compartimento como estão.
6. Clique em **Next** (Próximo) no final da página e, na tela de revisão, clique em **Create** (Criar).

_Isso vai gerar automaticamente a sua `vcn-principal`, a `public subnet-vcn-principal` (sub-rede pública) e as tabelas de rotas necessárias._

## 🛠️ Passo 1: Criação da Instância no Painel

No menu lateral, vá em **Compute** > **Instances** e clique em **Create instance**.

### 1.1. Imagem e Forma (Shape)

- **Imagem:** Clique em _Alterar imagem_, escolha **Canonical Ubuntu 24.04 Minimal aarch64** (versão ARM).
- **Forma (Shape):** Clique em _Alterar forma_, selecione a aba **Ampere** e marque a caixa **VM.Standard.A1.Flex**.
- **Recursos:** Aloque o limite máximo gratuito: **4 OCPUs** e **24 GB** de memória RAM.

### 1.2. Configuração de Rede (Networking)

- **Rede:** Selecione sua Rede Virtual existente (ex: `vcn-principal`).
- **Sub-rede:** Selecione a sub-rede pública regional.
- **IP Público:** Certifique-se de marcar a opção **Atribuir um endereço IPv4 público automaticamente**.

### 1.3. Chaves SSH (Crucial)

- Selecione **Gerar um par de chaves para mim** (ou faça o upload da sua pública se preferir).
- ⚠️ **Obrigatório:** Clique no botão **Fazer download da chave privada** e salve o arquivo `.key` no seu computador. Sem ele, você perderá o acesso definitivo à VPS.

### 1.4. Armazenamento (Boot Volume)

- Ative a opção **Especifique um tamanho do volume de inicialização personalizado**.
- Altere o tamanho padrão de 46.6 GB para **200 GB** (limite máximo do Free Tier).
- Deixe o desempenho (VPU) em **10** (Balanceado).

_Role até o fim da página de Revisão e clique em **Criar**. Com a conta PAYG, a instância será criada imediatamente._

## 💻 Passo 2: Permissões da Chave no Windows (PowerShell)

O OpenSSH do Windows recusa conexões se o arquivo da chave privada estiver exposto a outros usuários do sistema.

1. Mova o arquivo baixado para `C:\Users\SEU_USUARIO\.ssh\oracle.key`.
2. Clique com o botão direito no arquivo `oracle.key` > **Propriedades** > aba **Segurança** > **Avançado**.
3. Clique em **Desabilitar herança** e selecione **Remover todas as permissões herdadas** (a lista deve ficar vazia).
4. Clique em **Adicionar** > **Selecionar uma entidade de segurança**.
5. Digite seu usuário exato do Windows, clique em **Verificar Nomes** e dê **OK**.
6. Marque a caixa **Controle total** e salve todas as janelas.

### 2.1. Primeiro Acesso SSH

Abra o PowerShell e execute:

```powershell
ssh -i "C:\Users\SEU_USUARIO\.ssh\oracle.key" ubuntu@IP_PUBLICO_DA_VPS

```

_Digite `yes` quando o terminal perguntar se confia no host._

## 🧱 Passo 3: Configuração do Firewall Duplo

A imagem padrão da Oracle vem com bloqueio total de tráfego de entrada. É obrigatório liberar as portas desejadas (ex: `80` para HTTP e `443` para HTTPS) no painel web e no sistema operacional.

### 3.1. Barreira 1: Painel Web (Security List)

1. No menu da instância, clique na aba **Rede** e acesse o link da sua sub-rede pública.
2. Na aba **Regras de segurança**, clique em **Adicionar Regras de Entrada**.
3. Configure a regra:

- **Tipo de Origem:** CIDR
- **CIDR de Origem:** `0.0.0.0/0` (Qualquer IP da internet)
- **Protocolo IP:** TCP
- **Intervalo de Portas de Destino:** `80,443`

4. Clique em **Adicionar Regras de Entrada**.

### 3.2. Barreira 2: Sistema Operacional (iptables)

Logado na VPS via SSH, execute os comandos abaixo para liberar as portas no Ubuntu e salvar as regras permanentemente:

```bash
# Libera as portas HTTP e HTTPS nas tabelas de INPUT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT

# Salva as regras para persistirem após reinicializações
sudo netfilter-persistent save
```

Pronto! Infraestrutura base configurada, segura e pronta para receber o Docker e seus containers. 🚀
