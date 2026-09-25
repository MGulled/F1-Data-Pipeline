resource "azurerm_resource_group" "f1" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_storage_account" "f1" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.f1.name
  location                 = azurerm_resource_group.f1.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  is_hns_enabled           = true # required for ADLS Gen2
}

resource "azurerm_storage_container" "staging" {
  name                  = "staging"
  storage_account_name  = azurerm_storage_account.f1.name
  container_access_type = "private"
}

resource "azurerm_databricks_workspace" "f1" {
  name                = var.databricks_workspace_name
  resource_group_name = azurerm_resource_group.f1.name
  location            = azurerm_resource_group.f1.location
  sku                 = var.databricks_sku
}