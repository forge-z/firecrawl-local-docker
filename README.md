# Firecrawl Local (Rust) no Coolify / Beelink

Pacote de exemplo **não oficial** e ainda **não testado em um host Docker real**.
Baseado no `apps/local` do [repositório oficial](https://github.com/firecrawl/firecrawl/tree/main/apps/local), **não** no `docker-compose.yaml` da raiz do Firecrawl.

## O que este pacote entrega

- 1 container em execução, com o binário `firecrawl-local` compilado em Rust em um build multistage.
- API HTTP compatível com as rotas Firecrawl **v2** de scrape, crawl, map e batch scrape, na porta interna **3002**.
- Chromium instalado, iniciado sob demanda para renderizar páginas com JavaScript.
- Execução como usuário não privilegiado; Chromium com sandbox e perfil seccomp baseado no perfil oficial do Playwright.
- Bearer token obrigatório; o `serve` escuta em `0.0.0.0` somente com token.
- Cloud totalmente desativada (`FIRECRAWL_CLOUD=off`). **Search não funciona localmente**: `/v2/search` retorna erro `CLOUD_ONLY`.
- Sem Postgres, Redis ou RabbitMQ; sem exposição direta de porta na definição para Coolify.

**Importante:** Docker reduz a simplicidade do “binário único”: a imagem contém Chromium e dependências, que ocupam espaço. Os 11 MB de RAM anunciados pelo Firecrawl são para o processo ocioso, NÃO para a imagem nem para um navegador ativo.

## Arquivos

- `Dockerfile`: build Rust multistage + Chromium no runtime.
- `docker-compose.yml`: configuração padrão para Coolify.
- `entrypoint.sh`: inicialização da API, autenticação e validação de hostname.
- `seccomp_profile.json`: perfil Playwright para permitir sandbox de Chromium sem `seccomp=unconfined`.
- `.env.example`: exemplo de variáveis.
- `docker-compose.local.yml`: mapeia a porta **apenas para 127.0.0.1**, para testes Docker fora do Coolify.

## 1. Preparação para o Coolify

1. Coloque **todos os arquivos** deste pacote na raiz de um repositório Git seu. A versão do Firecrawl é clonada durante o `docker build`; não é necessário copiar o projeto Firecrawl inteiro.
2. Gere uma chave aleatória com `openssl rand -hex 32`.
3. No **Coolify**, crie uma aplicação a partir do repositório Git, usando **Docker Compose** e o arquivo `docker-compose.yml` da raiz. Evite ativar modo `Raw` caso dependa das funcionalidades automáticas de domínio do Coolify.
4. Configure as variáveis de ambiente da aplicação:
   - `FIRECRAWL_LOCAL_TOKEN`: chave aleatória do passo 2 (secreta).
   - `FIRECRAWL_ALLOWED_HOST`: seu domínio, **somente hostname**; por exemplo `firecrawl.seudominio.com` (sem `https://` e sem porta).
   - `FIRECRAWL_REF`: opcional; por padrão, commit conhecido de 18/11/2026 que contém a implementação Firecrawl Local 0.1.1.
   - `FIRECRAWL_LOCAL_SCROLL`: opcional, `true` se quiser testar scroll em páginas renderizadas.
5. Na configuração de domínios do serviço `firecrawl`, aponte `https://firecrawl.seudominio.com` para a **porta interna 3002**. O Compose inclui `SERVICE_FQDN_FIRECRAWL_3002` para facilitar a geração de domínio nas versões do Coolify que a suportam. Verifique o domínio efetivamente atribuído e assegure que combina com `FIRECRAWL_ALLOWED_HOST`.
6. Faça o deploy e aguarde o container ficar **healthy**.

**Não** configure ports públicos como `3002:3002` no Compose usado pelo Coolify. A aplicação deve ser publicada apenas pelo proxy HTTPS do Coolify, com token obrigatório.

O `seccomp_profile.json` precisa existir junto com o Compose **no host que faz o deploy**. O arquivo incluído é derivado do [perfil oficial do Playwright](https://github.com/microsoft/playwright/blob/main/utils/docker/seccomp_profile.json).

### Requisitos importantes do host

- Docker Engine com suporte a seccomp e namespaces de usuário.
- O kernel/LSM (AppArmor, por exemplo) deve permitir que Chromium crie namespaces de usuário.
- Espaço em disco e RAM suficientes **para a compilação Rust**. Os 2 GB do Compose limitam o container **de execução**, não o processo de build. Compilar em um Beelink modesto pode pressionar CPU e RAM, mesmo com `CARGO_BUILD_JOBS=2`.
- Arquitetura do Beelink x86-64 (amd64); imagem `rust:1-bookworm` também oferece suporte a outras arquiteturas, mas este pacote foi pensado para amd64.

## 2. Testar a API externa

Use seus próprios domínio e token:

```bash
export FC_API='https://firecrawl.seudominio.com'
export FC_TOKEN='SEU_TOKEN_AQUI'

# O healthcheck externo também requer autenticação.
curl -fsS -H "Authorization: Bearer $FC_TOKEN" "$FC_API/health"

# Extração HTML -> Markdown totalmente local.
curl -fsS "$FC_API/v2/scrape" \
  -H "Authorization: Bearer $FC_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://example.com","formats":["markdown"]}'

# Descobrir URLs de um domínio.
curl -fsS "$FC_API/v2/map" \
  -H "Authorization: Bearer $FC_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://example.com"}'
```

O `/v2/crawl` inicia um job assíncrono; o resultado é consultado com `GET /v2/crawl/<id>` enquanto o serviço estiver em execução. Jobs ficam apenas na memória e expiram depois de aproximadamente uma hora.

### Testar com SDK

```python
from firecrawl import Firecrawl

fc = Firecrawl(api_url='https://firecrawl.seudominio.com', api_key='SEU_TOKEN_AQUI')
print(fc.scrape('https://example.com').markdown)
```

Algumas versões de SDK exigem formatos ligeiramente diferentes de configuração. O principal contrato é `Authorization: Bearer TOKEN` e o endpoint v2.

## 3. Testar com Docker Compose fora do Coolify

```bash
cp .env.example .env
# Edite .env para colocar TOKEN e HOST reais.
docker compose -f docker-compose.yml -f docker-compose.local.yml up -d --build
curl -fsS -H 'Authorization: Bearer SEU_TOKEN_AQUI' http://127.0.0.1:3002/health
```

A porta fica acessível **somente no loopback do host**. De outra máquina, use um túnel SSH ou o proxy HTTPS do Coolify.

## Diagnóstico

- `401 UNAUTHORIZED`: token ausente ou incorreto. Também afeta `/health`.
- `403 HOST_NOT_ALLOWED`: o hostname em `FIRECRAWL_ALLOWED_HOST` não coincide com o `Host` recebido. Não inclua `https://` ou `:3002` na variável.
- `502/504` no Coolify: verifique se o proxy aponta para **3002** e se o container está healthy.
- `No usable sandbox` / erro de namespaces: o host pode bloquear o sandbox do Chromium (seccomp, AppArmor, configuração de user namespaces). **Não** use `--no-sandbox` nem `seccomp=unconfined` como correção de produção; examine a política do host e o perfil do Playwright.
- `CLOUD_ONLY` em `/v2/search`: esperado; **não existe busca self-hosted no Firecrawl Local**.
- Falhas em páginas que dependem de JavaScript: confira a detecção do Chromium, uso de `/dev/shm`, memória e proteção antibot. A Cloud continua podendo superar o Local em sites protegidos.
- `json`, `summary` e interações via `actions` não estão implementados localmente nesta versão; capturas de tela requerem Chromium.
- Se o `build` falhar devido a mudanças de dependências, mantenha/ajuste `FIRECRAWL_REF` para um commit verificado. O repositório upstream evolui rapidamente.

## Observações de segurança e custos

- `FIRECRAWL_CLOUD=off` mantém Search e fallbacks Cloud desativados; não exige nem usa créditos do Firecrawl Cloud.
- Os destinos privados/loopback são bloqueados pelo servidor por padrão, o que reduz risco de SSRF.
- O token protege todas as rotas, mas **não substitui HTTPS**, rate limiting e restrições de acesso no proxy.
- O Coolify não gerencia automaticamente certificados/rotas quando o Compose roda em modo `Raw` sem labels adequados.
- O MCP não roda dentro deste container. Para usá-lo, configure o [firecrawl-mcp](https://github.com/firecrawl/firecrawl-mcp-server) no cliente ou gateway e direcione-o à API HTTP com o mesmo token.

## Referências

- [Firecrawl Local README](https://github.com/firecrawl/firecrawl/blob/main/apps/local/README.md)
- [PR de introdução do Firecrawl Local](https://github.com/firecrawl/firecrawl/pull/5685)
- [Playwright — Docker](https://playwright.dev/docs/docker)
- [Coolify — Docker Compose](https://coolify.io/docs/applications/builds/docker-compose)
