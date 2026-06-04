# ── Senhas dos RDS (geradas pelo Terraform, ficam no tfstate) ─────────────────
resource "random_password" "rds" {
  for_each = local.rds_instances

  length  = 24
  special = true
  # Evita caracteres que quebram a URL de conexão mesmo após urlencode
  override_special = "!#$%&*-_=+?"
}

# ── Secrets Manager — connection strings consumidas pelo External Secrets ──────
# Nome fixo togglemaster/rds/<svc>, propriedade connection_string → casa com os
# ExternalSecrets em k8s/<svc>/externalsecret.yaml (sem mudança nos manifestos).
module "rds_secret" {
  source   = "github.com/vitorfprado/terraform-aws-modules//secrets-manager?ref=main"
  for_each = local.rds_instances

  name        = "${var.system}/rds/${each.key}"
  description = "Credenciais RDS do ${each.key}-service"

  secret_key_value = {
    engine            = "postgres"
    host              = module.rds[each.key].db_instance_address
    port              = "5432"
    database          = each.value.db_name
    username          = each.value.username
    password          = random_password.rds[each.key].result
    connection_string = "postgres://${each.value.username}:${urlencode(random_password.rds[each.key].result)}@${module.rds[each.key].db_instance_address}:5432/${each.value.db_name}?sslmode=require"
  }

  recovery_window_in_days = 0 # lab — exclui na hora

  tags = local.tags
}
