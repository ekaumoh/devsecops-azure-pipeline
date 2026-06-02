terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
  required_version = ">= 1.3.0"

  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "stterraformstate18262"
    container_name       = "tfstate"
    key                  = "devsecops.terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
  storage_use_azuread = true
}