terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }

  # Bootstrap usa state LOCAL (cria o backend remoto que os demais stages usam).
  # Rode uma única vez, localmente, com credenciais de admin.
}

provider "aws" {
  region = var.region
}
