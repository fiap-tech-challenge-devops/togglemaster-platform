terraform {
  # Backend parcial: bucket/region/dynamodb_table vêm via -backend-config
  # (ver iac/README.md e os workflows). O bucket/tabela são criados no stage 0 (bootstrap).
  backend "s3" {
    key = "togglemaster/infra.tfstate"
  }
}
