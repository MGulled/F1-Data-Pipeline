output "resource_group_name" {
  value = azurerm_resource_group.f1.name
}

output "storage_account_name" {
  value = azurerm_storage_account.f1.name
}

output "databricks_workspace_url" {
  value = azurerm_databricks_workspace.f1.workspace_url
}