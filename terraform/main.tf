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

resource "databricks_catalog" "f1" {
  name    = "f1_workspace"
  comment = "F1 data engineering project catalog"
}

resource "databricks_schema" "bronze" {
  catalog_name = databricks_catalog.f1.name
  name         = "bronze"
}

resource "databricks_schema" "silver" {
  catalog_name = databricks_catalog.f1.name
  name         = "silver"
}

resource "databricks_schema" "gold" {
  catalog_name = databricks_catalog.f1.name
  name         = "gold"
}


resource "databricks_job" "f1_pipeline" {
  name = "f1_pipeline"

  schedule {
    quartz_cron_expression = "0 0 8 ? * MON"
    timezone_id            = "Europe/Oslo"
    pause_status           = "UNPAUSED"
  }

  email_notifications {
    on_failure = [var.notification_email]
  }

  task {
    task_key = "bronze_circuits"
    notebook_task {
      notebook_path = "${var.notebook_base_path}/bronze/bronze_circuits"
    }
  }

  task {
    task_key = "bronze_constructors"
    notebook_task {
      notebook_path = "${var.notebook_base_path}/bronze/bronze_constructors"
    }
  }

  task {
    task_key = "bronze_drivers"
    notebook_task {
      notebook_path = "${var.notebook_base_path}/bronze/bronze_drivers"
    }
  }

  task {
    task_key = "bronze_races"
    notebook_task {
      notebook_path = "${var.notebook_base_path}/bronze/bronze_races"
    }
  }

  task {
    task_key = "bronze_results"
    notebook_task {
      notebook_path = "${var.notebook_base_path}/bronze/bronze_results"
    }
  }

  task {
    task_key = "silver_circuits"
    depends_on {
      task_key = "bronze_circuits"
    }
    notebook_task {
      notebook_path = "${var.notebook_base_path}/silver/silver_circuits"
    }
  }

  task {
    task_key = "dim_circuits"
    depends_on {
      task_key = "silver_circuits"
    }
    notebook_task {
      notebook_path = "${var.notebook_base_path}/gold/dim_circuits"
    }
  }

  task {
    task_key = "silver_constructors"
    depends_on {
      task_key = "bronze_constructors"
    }
    notebook_task {
      notebook_path = "${var.notebook_base_path}/silver/silver_constructors"
    }
  }

  task {
    task_key = "dim_constructors"
    depends_on {
      task_key = "silver_constructors"
    }
    notebook_task {
      notebook_path = "${var.notebook_base_path}/gold/dim_constructors"
    }
  }

  task {
    task_key = "silver_drivers"
    depends_on {
      task_key = "bronze_drivers"
    }
    notebook_task {
      notebook_path = "${var.notebook_base_path}/silver/silver_drivers"
    }
  }

  task {
    task_key = "silver_races"
    depends_on {
      task_key = "bronze_races"
    }
    notebook_task {
      notebook_path = "${var.notebook_base_path}/silver/silver_races"
    }
  }

  task {
    task_key = "dim_races"
    depends_on {
      task_key = "silver_races"
    }
    depends_on {
      task_key = "silver_circuits"
    }
    notebook_task {
      notebook_path = "${var.notebook_base_path}/gold/dim_races"
    }
  }

  task {
    task_key = "silver_results"
    depends_on {
      task_key = "bronze_results"
    }
    notebook_task {
      notebook_path = "${var.notebook_base_path}/silver/silver_results"
    }
  }

  task {
    task_key = "dim_drivers"
    depends_on {
      task_key = "silver_drivers"
    }
    depends_on {
      task_key = "silver_results"
    }
    notebook_task {
      notebook_path = "${var.notebook_base_path}/gold/dim_drivers"
    }
  }

  task {
    task_key = "fact_results"
    depends_on {
      task_key = "dim_races"
    }
    depends_on {
      task_key = "dim_constructors"
    }
    depends_on {
      task_key = "dim_drivers"
    }
    depends_on {
      task_key = "silver_results"
    }
    notebook_task {
      notebook_path = "${var.notebook_base_path}/gold/fact_results"
    }
  }
}