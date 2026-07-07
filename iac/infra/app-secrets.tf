# ── Secrets de aplicação (não-RDS) ────────────────────────────────────────────
# Diferente dos secrets de RDS (secrets.tf), estes são da própria aplicação.
# Usamos recursos nativos por causa do ciclo de vida específico de cada um.

# MASTER_KEY do auth-service — chave-raiz que protege o /admin/keys.
# Gerada pelo Terraform (fica no tfstate + Secrets Manager); recupere via CLI quando precisar.
resource "random_password" "master_key" {
  length  = 32
  special = false # alfanumérica — evita problemas ao passar em headers/curl
}

resource "aws_secretsmanager_secret" "app_auth" {
  name                    = "${var.system}/app/auth"
  description             = "MASTER_KEY do auth-service (chave-raiz do /admin/keys)"
  recovery_window_in_days = 0 # lab — exclui na hora
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "app_auth" {
  secret_id     = aws_secretsmanager_secret.app_auth.id
  secret_string = jsonencode({ MASTER_KEY = random_password.master_key.result })
}

# SERVICE_API_KEY do evaluation-service — placeholder criado aqui só para o secret
# EXISTIR. O valor REAL é gerado pela esteira (passo "Bootstrap SERVICE_API_KEY"),
# então ignoramos mudanças no valor para o apply não reverter a key gerada.
resource "aws_secretsmanager_secret" "app_evaluation" {
  name                    = "${var.system}/app/evaluation"
  description             = "SERVICE_API_KEY do evaluation-service (valor gerado pela esteira)"
  recovery_window_in_days = 0
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "app_evaluation" {
  secret_id     = aws_secretsmanager_secret.app_evaluation.id
  secret_string = jsonencode({ SERVICE_API_KEY = "placeholder" })

  lifecycle {
    ignore_changes = [secret_string] # a esteira sobrescreve com a key real
  }
}
