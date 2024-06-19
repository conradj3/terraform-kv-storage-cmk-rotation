# Set Local Variables
locals {
    current_user_id = coalesce(var.msi_id, data.azurerm_client_config.current.object_id) # Provide as var_msi_id or assume user.
}

# Generate Random Resource Group Name
resource "random_pet" "rg_name" {
    prefix = var.resource_group_name_prefix
}

# Create Resource Group
resource "azurerm_resource_group" "rg" {
    name     = random_pet.rg_name.id
    location = var.resource_group_location
}

# Collect the current user's object ID
data "azurerm_client_config" "current" {}

# Generate Random Key Vault Name
resource "random_string" "azurerm_key_vault_name" {
    length  = 13
    lower   = true
    numeric = false
    special = false
    upper   = false
}


# Create Key Vault
resource "azurerm_key_vault" "vault" {
    name                       = coalesce(var.vault_name, "vault-${random_string.azurerm_key_vault_name.result}")
    location                   = azurerm_resource_group.rg.location
    resource_group_name        = azurerm_resource_group.rg.name
    tenant_id                  = data.azurerm_client_config.current.tenant_id
    sku_name                   = var.sku_name
    soft_delete_retention_days = 7
    purge_protection_enabled = true

    access_policy {
        tenant_id = data.azurerm_client_config.current.tenant_id
        object_id = local.current_user_id # See LC3

        key_permissions    = var.key_permissions
        secret_permissions = var.secret_permissions
    }
}


# Create Null Resource to trigger replacement of Key Vault Key
resource "null_resource" "cmk_replacement_trigger" {
    triggers = {
        today = timestamp() # https://developer.hashicorp.com/terraform/language/functions/timestamp
        # Change this date from today to your rotation
    }
}

# Create Time Offset to set Key Vault Key Expiration Date
resource "time_offset" "offset" {
    offset_days = 365

    lifecycle {
        replace_triggered_by = [null_resource.cmk_replacement_trigger]
    }
}

# Create Random String for Key Vault Key Name
resource "random_string" "azurerm_key_vault_key_name" {
    length  = 13
    lower   = true
    numeric = false
    special = false
    upper   = false
}

# Create Key Vault Key
resource "azurerm_key_vault_key" "key" {
    name         = "customer-managed-key-${formatdate("YYYYMMDD-hhmm", timestamp())}"
    key_vault_id = azurerm_key_vault.vault.id
    key_opts = var.key_ops
    key_size = var.key_size
    key_type = var.key_type
    expiration_date = time_offset.offset.rfc3339

      lifecycle {
    create_before_destroy = true
  }
}

# Create User Assigned Identity
resource "azurerm_user_assigned_identity" "key_vault_crypto" {
    location            = azurerm_resource_group.rg.location
    name                = "kv_storage_user_assigned_id"
    resource_group_name = azurerm_resource_group.rg.name
}

# Create Role Assignment for Key Vault Crypto Service Encryption User
resource "azurerm_role_assignment" "key_vault_crypto" {
    scope                = azurerm_key_vault.vault.id
    role_definition_name = "Key Vault Crypto Service Encryption User"
    principal_id         = azurerm_user_assigned_identity.key_vault_crypto.principal_id
}

# Create the Key Vault 'Admin User Group' Access Policy Group
resource "azurerm_key_vault_access_policy" "key_vault_access" {
    key_vault_id = azurerm_key_vault.vault.id
    tenant_id    = data.azurerm_client_config.current.tenant_id
    object_id    = azurerm_user_assigned_identity.key_vault_crypto.principal_id

    key_permissions = [
        "Get",
        "UnwrapKey",
        "WrapKey"
    ]

    certificate_permissions = [
    ]

    secret_permissions = [
    ]

    storage_permissions = [
    ]
}

# Random String for Storage Account Name
resource "random_string" "azurerm_storage_account" {
    length  = 24
    lower   = true
    numeric = false
    special = false
    upper   = false
}

# Storage Account with Customer Managed Key
resource "azurerm_storage_account" "example" {
    name                     = random_string.azurerm_storage_account.result
    resource_group_name      = azurerm_resource_group.rg.name
    location                 = azurerm_resource_group.rg.location
    account_kind                      = "StorageV2"
    account_tier                      = "Standard"
    account_replication_type          = "LRS"
    cross_tenant_replication_enabled  = true
    enable_https_traffic_only         = true
    min_tls_version                   = "TLS1_2"
    infrastructure_encryption_enabled = true
    public_network_access_enabled     = false
    allow_nested_items_to_be_public   = false
  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.key_vault_crypto.id]
  }
    network_rules {
        default_action             = "Deny"
        bypass                     = ["Logging", "Metrics", "AzureServices"]
        virtual_network_subnet_ids = []
    }

    customer_managed_key {
        user_assigned_identity_id = azurerm_user_assigned_identity.key_vault_crypto.id
        key_vault_key_id          = azurerm_key_vault_key.key.id
    }
}
