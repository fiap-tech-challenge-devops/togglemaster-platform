# Documentação de Deploy — ToggleMaster no Kubernetes (Amazon EKS)

**Projeto:** ToggleMaster (FIAP — Fase 2)
**Data:** Junho de 2026
**Escopo:** Desafios encontrados ao **implantar** os 5 microsserviços no Kubernetes (Amazon EKS) e integrá-los aos recursos gerenciados da AWS (RDS, ElastiCache, SQS, DynamoDB). Foca na camada de **aplicação / Kubernetes / AWS**. A Infraestrutura como Código (Terraform) e as esteiras de CI/CD ficam **fora do escopo avaliado desta fase** — aqui são citadas apenas como a **decisão de custo** que motivou seu uso (ver Desafio 9), sem detalhar sua implementação.

---

## Visão Geral

Depois da containerização (ver `01-containerizacao.md` em cada serviço) e do `docker-compose` funcionando localmente, o passo seguinte foi subir o ecossistema para a nuvem.

A lição transversal de toda esta etapa: **o ambiente local (docker-compose) mascara os problemas da nuvem**. No laptop, os bancos sobem com schema pronto, não há limite de pods por máquina, e os segredos estão num `.env`. Na AWS, cada uma dessas premissas cai por terra. Este documento registra os desafios reais e como foram resolvidos.

---

## Desafio 1 — Free Tier: a instância elegível só comporta ~4 pods

### O que aconteceu

A primeira tentativa usou uma instância elegível ao **Free Tier** (`t3.micro`) como nó do cluster. Ao implantar os 5 microsserviços, a maioria dos pods ficou em **`Pending`** — o nó não tinha "vagas" suficientes.

### Por que

No EKS, o plugin de rede **VPC CNI** dá a **cada pod um IP real de uma ENI** (placa de rede) da instância. O número máximo de pods por nó é, portanto, limitado pela quantidade de ENIs/IPs que o tipo de instância suporta:

```
maxPods = (ENIs × (IPs por ENI − 1)) + 2
t3.micro → (2 × (2 − 1)) + 2 = 4 pods
```

E desses 4, vários slots já são ocupados por pods **de sistema** (CoreDNS, kube-proxy, aws-node). Sobra praticamente nada para as aplicações. **5 microsserviços não cabem em 4 pods.**

### Solução

Sair do Free Tier e usar uma instância maior (`t3.medium`, que suporta **17 pods**). Foi o **primeiro motivo** do upgrade do plano da conta AWS.

---

## Desafio 2 — Free Tier: não comporta os 3 bancos RDS necessários

### O que aconteceu

A arquitetura exige **3 instâncias RDS PostgreSQL independentes** (uma para `auth`, uma para `flags`, uma para `targeting`). O Free Tier não comportou as três.

### Por que

O Free Tier do RDS cobre apenas **~750 horas/mês de uma única instância elegível** (`db.t3.micro`, single-AZ). Manter **3 instâncias rodando 24/7** ultrapassa de longe essa cobertura — na prática, esbarramos no limite ao tentar manter mais de 2 bancos.

### Solução

Sair do Free Tier e aceitar o custo das 3 instâncias RDS. Foi o **segundo motivo** do upgrade do plano.

> **Nota de arquitetura:** os 3 bancos separados são uma exigência do padrão *database-per-service* (cada microsserviço dono do seu schema). Consolidar em 1 banco economizaria, mas quebraria o isolamento que o desafio pede.

---

## Desafio 3 — Limite de pods por nó persiste mesmo fora do Free Tier

### O que aconteceu

Mesmo na `t3.medium`, ao exercitar a **escalabilidade** (gerar carga e deixar o autoscaling criar réplicas), os pods voltaram a ficar **`Pending`** com o evento:

```
0/1 nodes are available: 1 Too many pods.
```

O nó bateu o teto de **17 pods** — sistema + aplicações + réplicas novas não cabiam.

### Por que

O mesmo limite do Desafio 1, só que num patamar maior (17 em vez de 4). Sob escala, 5 apps + réplicas de HPA + pods de sistema ultrapassam 17 facilmente.

### Solução

Duas frentes, ambas em conceitos de Kubernetes/EKS:

1. **Prefix Delegation** no VPC CNI — em vez de 1 IP por vez, a ENI passa a alocar **blocos (/28) de 16 IPs**, elevando o teto de pods do nó (de 17 para ~110 numa `t3.medium`).
2. **Escala de nós sob demanda** — adicionar capacidade automaticamente quando os pods não cabem, em vez de depender de um único nó fixo.

---

## Desafio 4 — O RDS sobe VAZIO (o schema não é criado sozinho)

### O que aconteceu

Com tudo no ar, o `auth-service` quebrou na primeira chamada que tocava o banco:

```
ERROR: relation "api_keys" does not exist (SQLSTATE 42P01)
```

As tabelas simplesmente **não existiam** no RDS.

### Por que

Cada serviço tem um `db/init.sql` no repositório. **Localmente**, a imagem oficial do PostgreSQL roda esse script automaticamente no primeiro boot (via `/docker-entrypoint-initdb.d`). **No RDS**, isso não acontece — a AWS entrega uma instância PostgreSQL **vazia**. Ninguém aplica o `init.sql`.

```
LOCAL (docker-compose)              NUVEM (RDS)
container Postgres roda          →  instância sobe VAZIA
o init.sql no primeiro boot         (nada cria as tabelas)
```

### Solução

Aplicar o schema de cada serviço (`api_keys`, `flags`, `targeting_rules`) **no RDS, antes** das aplicações precisarem dele. Como o RDS vive em **subnets privadas** (só acessível de dentro da VPC), o SQL é executado por um **pod efêmero** dentro do cluster, que alcança o banco e roda os scripts (idempotentes, com `CREATE TABLE IF NOT EXISTS`).

---

## Desafio 5 — Segredos que a aplicação gera em runtime (MASTER_KEY / SERVICE_API_KEY)

### O que aconteceu

Dois segredos não existiam de antemão para serem simplesmente colocados num `Secret` do Kubernetes:

- `auth-service` exige um **`MASTER_KEY`** (token de admin) para criar chaves de API.
- `evaluation-service` exige um **`SERVICE_API_KEY`** para chamar os outros serviços — e essa chave é **gerada pelo próprio `auth-service`** (`POST /admin/keys`).

Ou seja: um segredo (`SERVICE_API_KEY`) só pode ser criado **depois** que a aplicação está no ar — um problema de **ovo e galinha**.

### Por que

No `docker-compose`, esses valores ficam num `.env` chumbado. Em produção, chumbar segredo em manifesto (mesmo em base64) é inseguro, e o `SERVICE_API_KEY` nem sequer é conhecido até o `auth-service` rodar.

### Solução

- **`MASTER_KEY`**: gerado uma vez e guardado no **AWS Secrets Manager**, injetado no pod como variável de ambiente a partir do `Secret`.
- **`SERVICE_API_KEY`**: gerado **após** o `auth-service` subir (chamando o endpoint de criação de chave) e então persistido como segredo e injetado no `evaluation-service`. A ordem importa: banco com schema → `auth-service` no ar → gerar a chave → injetar no consumidor.

> Aprendizado: nem todo segredo é estático. Alguns são **derivados em runtime** e exigem um passo de *bootstrap* depois do serviço de origem estar saudável.

---

## Desafio 6 — O Ingress não remove o prefixo do path (404 nas rotas)

### O que aconteceu

Com o Ingress publicado, chamadas externas retornavam **404**:

```
GET http://<load-balancer>/auth/health   →  404 page not found
```

### Por que

O Ingress roteava `/auth` → `auth-service`, mas **não removia o prefixo `/auth`** antes de encaminhar. O `auth-service` serve `/health`, `/validate`, `/admin/keys` **na raiz** — ele recebia `/auth/health` e não conhecia essa rota.

```
cliente → /auth/health → (ingress NÃO tira o /auth) → app recebe /auth/health → 404
```

### Solução

Rotear pelos **paths reais que cada aplicação serve**, em vez de inventar prefixos:

| Path no Ingress | Serviço |
|---|---|
| `/validate`, `/admin` | auth-service |
| `/flags` | flag-service |
| `/rules` | targeting-service |
| `/evaluate` | evaluation-service |

Assim a requisição chega na aplicação exatamente na rota que ela espera, sem necessidade de *rewrite*.

---

## Desafio 7 — `apiVersion` da CRD incompatível com a versão instalada

### O que aconteceu

A aplicação dos manifestos de integração de segredos falhou com:

```
no matches for kind "ExternalSecret" in version "external-secrets.io/v1"
```

### Por que

Os manifestos declaravam `apiVersion: external-secrets.io/v1`, mas a versão do operador instalada no cluster servia a CRD em `external-secrets.io/**v1beta1**`. O Kubernetes rejeita qualquer recurso cujo `apiVersion` não corresponda a uma CRD **efetivamente registrada** no cluster.

### Solução

Alinhar o `apiVersion` dos manifestos à versão que a CRD instalada realmente serve (`v1beta1`). 

> Aprendizado: ao usar operadores/CRDs, o `apiVersion` do manifesto precisa casar com a versão da CRD instalada — não basta usar a versão "mais nova" da documentação.

---

## Desafio 8 — Volatilidade de nós SPOT e a dependência do HPA pelo metrics-server

### O que aconteceu

Durante um teste de carga, um nó (instância **SPOT**) ficou `NotReady`. Pouco depois, o HPA passou a mostrar:

```
TARGETS   cpu: <unknown>/70%
```

— ou seja, parou de escalar por CPU.

### Por que

Dois fatos encadeados:

1. **SPOT é capacidade interruptível** — a AWS pode recuperar a instância (ou ela ficar instável sob pressão), e o nó cai.
2. O **metrics-server** (que alimenta o HPA com métricas de CPU) rodava nesse nó. Quando o nó caiu, o endpoint do metrics-server sumiu → a *Metrics API* ficou indisponível → o HPA não tinha mais dado de CPU para decidir a escala (`<unknown>`).

### Solução

- Entender que o **HPA depende do metrics-server** estar saudável — sem ele, não há escala por CPU.
- Recuperar/substituir o nó para o metrics-server voltar.
- Para a robustez (ex.: gravação da demo), considerar **fallback on-demand** além do SPOT, evitando ficar sem capacidade no meio de um teste.

---

## Desafio 9 — Custo: sair do Free Tier tornou caro manter o ambiente 24/7

### O que aconteceu

Os upgrades dos **Desafios 1 e 2** (sair do Free Tier) resolveram a capacidade, mas criaram um novo problema: **custo contínuo**. Um cluster EKS + 3 instâncias RDS + ElastiCache + nós EC2 rodando **o tempo todo** geram cobrança 24/7 — inclusive de madrugada, em finais de semana, e em qualquer momento em que **ninguém está testando**.

### Por que

Recursos gerenciados e nós são cobrados **por tempo de existência**, não por uso. Como o projeto é de **estudo** (uso esporádico, em janelas de teste), manter tudo de pé permanentemente significaria pagar um mês inteiro por algumas horas de uso real.

### Solução (decisão de custo)

Optamos por **Infraestrutura como Código (IaC) + esteiras** justamente para **subir todo o ambiente sob demanda e destruí-lo após os testes** — pagando apenas pelas **janelas de uso**, e não o mês inteiro:

```
antes do teste  →  esteira de APPLY   sobe tudo (EKS, RDS, Redis, SQS, DynamoDB, apps)
durante         →  ambiente no ar só enquanto é necessário
depois do teste →  esteira de DESTROY derruba tudo  →  custo volta a zero
```

Assim, a adoção de IaC + esteiras **não foi um requisito da fase**, e sim uma **decisão de controle de custo**: a forma mais prática de ligar e desligar um ambiente inteiro de forma repetível, minimizando o gasto a apenas o tempo dos testes.

> **Nota de escopo:** a IaC (Terraform) e as esteiras **não fazem parte da entrega avaliada** desta fase. São citadas aqui exclusivamente porque a decisão de usá-las **nasceu deste problema de custo** — consequência direta de ter saído do Free Tier.

---

## Lições aprendidas

1. **O local mascara a nuvem.** Banco vazio, limite de pods por nó, segredos em `.env` — tudo "funciona" no `docker-compose` e quebra na AWS. Vale testar cedo na nuvem.
2. **Free Tier não comporta um ecossistema de microsserviços.** O teto de pods das instâncias elegíveis (~4) e a cobertura limitada de RDS (~1 instância) forçaram o upgrade do plano — não por escolha, mas por necessidade arquitetural (5 apps + 3 bancos).
3. **Rede do EKS é por IP de pod.** O número de pods por nó é limitado pelas ENIs/IPs do tipo de instância; sob escala, isso vira gargalo (resolvido com prefix delegation e mais capacidade de nó).
4. **Recursos gerenciados sobem "crus".** O RDS não roda o `init.sql`; inicializar o schema é responsabilidade do processo de deploy.
5. **Nem todo segredo é estático.** Alguns são gerados em runtime pela própria aplicação e exigem um passo de bootstrap ordenado.
6. **Manifesto precisa casar com o cluster.** Rotas do Ingress devem bater com os paths reais das apps, e o `apiVersion` dos recursos com as CRDs instaladas.
7. **SPOT é barato, mas volátil.** Componentes críticos (como o metrics-server, do qual o HPA depende) sofrem quando um nó SPOT cai — planejar resiliência.
8. **Sair do Free Tier tem custo contínuo.** Recursos de nuvem são cobrados por tempo de existência, não por uso. Para um projeto de estudo, subir e destruir o ambiente sob demanda concentra o gasto nas janelas de teste — origem da decisão (não-avaliada nesta fase) de usar IaC + esteiras.
