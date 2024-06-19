output "resource_group_name" {
    value = azurerm_resource_group.rg.name
}

output "key_vault_name" {
    value = azurerm_key_vault.vault.name
}

output "key_vault_uri" {
    value = azurerm_key_vault.vault.vault_uri
}

output "storage_account_name" {
    value = azurerm_storage_account.example.name
}

output "storage_account_primary_blob_endpoint" {
    value = azurerm_storage_account.example.primary_blob_endpoint
}

output "storage_account_primary_queue_endpoint" {
    value = azurerm_storage_account.example.primary_queue_endpoint
}

output "storage_account_primary_table_endpoint" {
    value = azurerm_storage_account.example.primary_table_endpoint
}

output "storage_account_primary_file_endpoint" {
    value = azurerm_storage_account.example.primary_file_endpoint
}