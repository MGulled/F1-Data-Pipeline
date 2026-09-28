variable "location" {
  description = "Azure region"
  type        = string
  default     = "Norway East"
}
variable "resource_group_name" {
  description = "Name of the resource group for the F1 project"
  type        = string
  default     = "rg-f1-project"
}
variable "storage_account_name" {
  description = "Name of the ADLS Gen2 storage account (must be globally unique, lowercase, no dashes)"
  type        = string
  default     = "stf1project"
}
variable "databricks_workspace_name" {
  description = "Name of the Databricks workspace"
  type        = string
  default     = "f1-workspace"
}
variable "databricks_sku" {
  description = "Databricks workspace SKU"
  type        = string
  default     = "premium"
}

variable "notebook_base_path" {
  description = "Base path to the notebooks in the Databricks workspace"
  type        = string
  default     = "/Workspace/Users/<email>/F1-Databricks-Project/notebooks"
}

variable "notification_email" {
  description = "Email address for job failure notifications"
  type        = string
  default     = "<email>"
}

