// config.js — configuração global self-hosted do Renovate para a plataforma Forgejo.
// ------------------------------------------------------------------------------
// Como usar: deixe este arquivo na RAIZ do repo central do bot (junto do
// .forgejo/workflows/renovate.yml). Guia: docs/forgejo.md (Parte 6).
//
// IMPORTANTE: num job do Forgejo Actions este arquivo NÃO é auto-carregado de
// /usr/src/app — o diretório de trabalho dos steps é o FORGEJO_WORKSPACE, não o
// WORKDIR da imagem. Por isso o workflow faz `actions/checkout` e define
// RENOVATE_CONFIG_FILE apontando para ${{ github.workspace }}/config.js.
// É um módulo CommonJS (module.exports), NÃO JSON — por isso dá pra ler env vars
// com process.env.
// ------------------------------------------------------------------------------

module.exports = {
  // Para instâncias Forgejo, a doc oficial exige platform=forgejo
  // (não reutilize platform: 'gitea').
  platform: 'forgejo',

  // SOMENTE a URL BASE pública (Cloudflare Tunnel). O Renovate acrescenta '/api/v1'
  // sozinho (e remove um /api/v1 final se você puser por engano); a barra final é
  // normalizada. Os jobs no dind alcançam o Forgejo só por esta URL.
  endpoint: 'https://git.exemplo.com/',

  // O token vem do secret RENOVATE_TOKEN (env var). NUNCA escreva o PAT no arquivo.
  // Escopos do PAT (Forgejo >= 1.20 / v15): repo R+W, user R, issue R+W,
  // organization R (para ler labels e times). Detalhes na Parte 6 do guia.
  token: process.env.RENOVATE_TOKEN,

  // Descobre e roda em todo repositório acessível pela conta-bot.
  // (Pula mirrors, repos sem permissão de push/pull e repos com PRs desabilitados.)
  autodiscover: true,
  // OPCIONAL: limitar o alcance, ex.: só uma organização:
  // autodiscoverFilter: ['minha-org/*'],

  // Identidade dos commits. Deve ser RFC5322 e bater com o e-mail da conta-bot.
  // (Também passado como RENOVATE_GIT_AUTHOR no workflow, por segurança.)
  gitAuthor: 'Renovate Bot <renovate@git.exemplo.com>',

  // Primeira execução: abre um PR de onboarding ("Configure Renovate") por repo
  // antes de fazer qualquer alteração. Nenhum PR de atualização é criado num repo
  // até você MERGEAR o onboarding dele. Para modo 100% automático (sem onboarding),
  // troque para `onboarding: false` e adicione `requireConfig: 'optional'`.
  onboarding: true,
  onboardingConfig: {
    $schema: 'https://docs.renovatebot.com/renovate-schema.json',
    extends: ['config:recommended'],
  },

  // Defaults amigáveis para homelab:
  dependencyDashboard: true, // cria 1 issue "Dependency Dashboard" por repo (visão única)
  prHourlyLimit: 0,          // sem teto de PRs/hora (default é 2); evita afunilar a 1ª varredura

  // platformAutomerge é true por padrão e é suportado no Forgejo >= v10.0.0
  // (esta instância é v15.0.2), então o automerge nativo da plataforma funciona.

  // OPCIONAL: auto-merge de atualizações patch + minor após o CI passar.
  // Descomente para habilitar. Só faz sentido com proteção de branch / status checks.
  // packageRules: [
  //   {
  //     matchUpdateTypes: ['patch', 'minor'],
  //     automerge: true,
  //     // platformAutomerge: true (default) — usa o auto-merge nativo do Forgejo.
  //   },
  // ],
};
