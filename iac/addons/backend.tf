terraform {
  # Backend parcial: bucket/region/dynamodb_table via -backend-config (ver iac/README.md).
  backend "s3" {
    key = "togglemaster/addons.tfstate"
  }
}
