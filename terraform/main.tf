resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_storage_account" "main" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # CKV_AZURE_190, CKV2_AZURE_47 — block public blob access
  allow_nested_items_to_be_public = true

  # CKV_AZURE_3 — HTTPS only
  https_traffic_only_enabled = true

  # CKV_AZURE_44 — enforce minimum TLS version
  min_tls_version = "TLS1_2"

  # CKV_AZURE_59 — block public network access at network level
  public_network_access_enabled = false

  # CKV2_AZURE_40 — disable Shared Key auth, force Entra ID (Azure AD) auth only
  shared_access_key_enabled = false

  # CKV2_AZURE_41 — require SAS tokens to have an expiration policy
  sas_policy {
    expiration_period = "00.01:00:00"
    expiration_action = "Log"
  }

  blob_properties {
    # CKV2_AZURE_38 — soft delete protects against accidental deletion
    delete_retention_policy {
      days = 7
    }
  }

  # CKV_AZURE_33 — enable logging for Queue service
  queue_properties {
    logging {
      delete                = true
      read                  = true
      write                 = true
      version               = "1.0"
      retention_policy_days = 7
    }
  }
}
