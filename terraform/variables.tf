variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-devsecops-demo"
}

variable "storage_account_name" {
  description = "Name of the storage account (must be globally unique, lowercase, 3-24 chars)"
  type        = string
}
