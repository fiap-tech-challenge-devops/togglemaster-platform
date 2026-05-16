# togglemaster-platform

Repositório central de artefatos compartilhados do projeto ToggleMaster (FIAP).

## Subindo o ambiente local

### Pré-requisitos

- Docker Desktop (ou Docker Engine + Docker Compose v2)

### 1. Configure as variáveis de ambiente (opcional)

```bash
cp .env.example .env
# Edite .env se quiser trocar senhas ou porta
```

Os valores padrão do `.env.example` já funcionam para desenvolvimento local sem nenhuma alteração.

### 2. Suba os serviços

Execute na pasta `togglemaster-platform/`:

```bash
docker compose up --build
```

Isso irá:
1. Construir a imagem do `auth-service` a partir de `../auth-service/`
2. Subir o PostgreSQL e executar `db/init.sql` (cria a tabela `api_keys`)
3. Subir o `auth-service` após o Postgres estar saudável

Para rodar em segundo plano:

```bash
docker compose up --build -d
```

Para parar e remover os contêineres:

```bash
docker compose down
```

Para parar e também remover os volumes (apaga os dados do banco):

```bash
docker compose down -v
```

---

## Testando os endpoints

### Health check

```bash
curl http://localhost:8001/health
```

Resposta esperada: `{"status":"ok"}`

### Criar uma chave de API

```bash
curl -X POST http://localhost:8001/admin/keys \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer admin-secreto-123" \
  -d '{"name": "meu-primeiro-servico"}'
```

Resposta esperada:
```json
{
  "name": "meu-primeiro-servico",
  "key": "tm_key_...",
  "message": "Guarde esta chave com segurança! Você não poderá vê-la novamente."
}
```

### Validar a chave criada

Substitua `tm_key_...` pela chave retornada no passo anterior:

```bash
curl http://localhost:8001/validate \
  -H "Authorization: Bearer tm_key_..."
```

Resposta esperada: `{"message":"Chave válida"}`

---

## Serviços nesta entrega

| Serviço        | Porta | Descrição                              |
|----------------|-------|----------------------------------------|
| auth-service   | 8001  | Microserviço de autenticação (Go)      |
| postgres       | 5432  | Banco de dados PostgreSQL              |
