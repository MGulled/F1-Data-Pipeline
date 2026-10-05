# F1 Data Engineering Pipeline

An end-to-end batch data pipeline built on Azure Databricks and Terraform — pulling
Formula 1 race data from the public Jolpica-F1 API through a bronze/silver/gold
medallion architecture, orchestrated as a scheduled Databricks Job.

<img width="1157" height="687" alt="bilde" src="https://github.com/user-attachments/assets/57dc5708-7f99-408c-81c5-562cebef5e3d" />


This is my second data engineering portfolio project, and it's deliberately built
differently from my [Olist ecommerce pipeline](https://github.com/MGulled/ecommerce-olist-databricks.git). Where Olist
uses Databricks Lakeflow Declarative Pipelines and dbt, this project uses plain
PySpark notebooks orchestrated with an explicit Databricks Job task graph, and
infrastructure provisioned entirely with Terraform instead of Databricks Asset
Bundles — to show a second, equally valid orchestration pattern rather than repeat
the first one.

## Table of Contents

- [Tech Stack](#tech-stack)
- [Architecture](#architecture)
- [Orchestration: Databricks Job](#orchestration-databricks-job)
- [Infrastructure as Code](#infrastructure-as-code)
- [Design Decisions](#design-decisions)
- [Challenges & How They Were Solved](#challenges--how-they-were-solved)
- [Repo Structure](#repo-structure)
- [Setup: Running This Yourself](#setup-running-this-yourself)

## Tech Stack

| Layer | Tool |
|---|---|
| Cloud platform | Azure |
| Storage | Azure Data Lake Storage Gen2 |
| Data platform | Databricks (notebooks, Unity Catalog) |
| Data source | [Jolpica-F1 API](https://github.com/jolpica/jolpica-f1) (Ergast-compatible REST API) |
| Transformation | PySpark |
| Orchestration | Databricks Jobs (explicit task graph, scheduled) |
| Infrastructure as Code | Terraform |

## Architecture

The pipeline follows a **bronze → silver → gold** medallion architecture:

**Bronze** — raw ingestion, schema-enforced but structurally untouched
- 5 tables (circuits, constructors, drivers, races, results), each read via
  `spark.read.schema(...)` against an explicit `StructType` matching the API's raw
  JSON shape — including nested structs (`Driver`, `Constructor`, `FastestLap`,
  `Location`)
- Schemas are declared explicitly rather than inferred, so a missing or renamed field
  fails loudly instead of silently returning nulls
- No joins, no flattening — bronze is a faithful, re-derivable archive of what the API
  actually returned

**Silver** — cleaned, typed, flattened, one table per source
- 5 tables, each built independently from its own bronze table
- Flattens nested structs into top-level columns, trims whitespace, title-cases
  display text, and casts every field to its correct type
- No cross-table joins at this layer — each table is cleaned on its own

**Gold** — dimensional star schema, built with PySpark joins
- Dimensions: `dim_drivers`, `dim_constructors`, `dim_circuits`, `dim_races`
- Fact: `fact_results` — holds only foreign keys and race-result measures (grid,
  position, points, status), joined against each dimension as a referential integrity
  check
- `dim_races` is enriched with circuit name and country via a join to `dim_circuits`,
  since that's a common slice for F1 analysis


## Orchestration: Databricks Job
<img width="1120" height="640" alt="Screenshot 2026-09-28 041526" src="https://github.com/user-attachments/assets/05635251-848f-4af1-a752-ffa30d0cdb21" />

A single Databricks Job, `f1_pipeline`, runs all 15 notebooks with explicit task
dependencies: each silver task depends on its own bronze task, each gold dimension
depends on its silver source(s), and `fact_results` depends on every dimension plus
silver results.


The job runs weekly, Mondays at 08:00 Europe/Oslo, after the Sunday race's results are
available. Every layer writes with `overwrite` rather than `append`, since each run
pulls the complete current season — appending would duplicate every race already
loaded. A failure notification is configured on the job, and the ingestion tasks carry
one automatic retry to absorb a brief API hiccup.

## Infrastructure as Code

Everything is provisioned with Terraform, defined in [`terraform/`](terraform/):

- Resource group, ADLS Gen2 storage account, and staging container
- Databricks workspace
- Unity Catalog catalog (`f1_workspace`) and three schemas (`bronze`, `silver`, `gold`)
- The full Databricks Job — task graph, schedule, and notifications — as a
  `databricks_job` resource, translated directly from the job definition

Remote state is stored in a separate Azure storage account (`stf1tfstate`), configured
via the `azurerm` backend in `backend.tf`.

## Design Decisions

- **Notebooks + Jobs over Lakeflow.** My Olist project already demonstrates Lakeflow
  Declarative Pipelines. This project shows the alternative — hand-written PySpark
  transforms with explicit task orchestration.
- **PySpark joins over dbt for gold.** Same reasoning — dbt is already proven
  elsewhere in my portfolio, so the star schema here is built with plain DataFrame
  joins instead.
- **Terraform over Databricks Asset Bundles.** Olist deploys via Asset Bundles and
  GitHub Actions; this project provisions infrastructure with Terraform, to show that
  tooling as well.
- **Bronze stays nested.** Flattening happens at silver, not bronze, so bronze remains
  independent of any transformation decisions made downstream.
- **No SCD Type 2.** Driver and constructor attributes barely change season to
  season, and the drivers endpoint doesn't expose team history directly. SCD Type 2
  wasn't a good fit for what this data actually models, so dimension tables are kept
  as straightforward overwrites.

## Challenges & How They Were Solved

**Driver pagination cap silently dropping rows.** The drivers bronze pull initially
made a single unpaginated request, which silently returned only the API's default
30-row page instead of the full season's driver list. This caused the gold
`fact_results` table to drop 15 result rows through its inner join to `dim_drivers`,
since those drivers' foreign keys didn't exist in the dimension. Caught by comparing
row counts between silver and gold rather than assuming a clean join; fixed by
paginating the drivers pull the same way as results, against the API's reported
`total`.

**A missing field that only broke things two steps later.** An early version of the
results extraction logic tagged each result with its `round` and `raceName`, but not
its `season`. This went unnoticed until a composite key (`Season` + `Round` +
`Driver_Id`) was needed to uniquely identify a result — at which point every row
silently had a null or default season. Traced back through silver, bronze, and the
schema definition to the actual extraction step, where the field had never been added
to the source data in the first place, and fixed there rather than patched downstream.

**Append-mode duplication on reruns.** Early Job runs used `append` for the results
tables across all three layers. Since each run pulls the *entire* current season
rather than incremental new rows, this duplicated every race on every run — a second
run of the job doubled the row count from 330 to 660. Fixed by switching to
`overwrite` throughout, since the pipeline re-fetches the full season fresh each time
rather than tracking incremental changes.

## Repo Structure

```
.
├── config/
│   └── f1_config.py                # shared constants, schemas, add_ingestion_metadata()
├── notebooks/
│   ├── bronze/                     # one notebook per source table, nested + schema-enforced
│   │   ├── bronze_circuits
│   │   ├── bronze_constructors
│   │   ├── bronze_drivers
│   │   ├── bronze_races
│   │   └── bronze_results
│   ├── silver/                     # flattened, typed, cleaned (one notebook per bronze table)
│   │   ├── silver_circuits
│   │   ├── silver_constructors
│   │   ├── silver_drivers
│   │   ├── silver_races
│   │   └── silver_results
│   └── gold/                       # star schema: dims + fact
│       ├── dim_circuits
│       ├── dim_constructors
│       ├── dim_drivers
│       ├── dim_races
│       └── fact_results
├── terraform/
│   ├── backend.tf                  # remote state config
│   ├── main.tf                     # resource group, storage, workspace, catalog, Job
│   ├── variables.tf
│   └── outputs.tf
└── README.md
```

## Setup: Running This Yourself

### Prerequisites

- An Azure subscription
- A Databricks workspace with Unity Catalog enabled
- [Terraform](https://developer.hashicorp.com/terraform/install) installed
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli), logged
  in via `az login`

### 1. Provision infrastructure with Terraform

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

This creates the resource group, ADLS Gen2 storage account, Databricks workspace,
Unity Catalog catalog/schemas, and the `f1_pipeline` Job definition.

### 2. Upload the notebooks

Import the notebooks under `notebooks/` into your Databricks workspace at the path
referenced by `notebook_base_path` in `variables.tf` (or update that variable to match
wherever you place them).

### 3. Run the pipeline

Trigger `f1_pipeline` manually from the Databricks Jobs UI for a first run, or wait
for its weekly schedule (Mondays, 08:00 Europe/Oslo). Verify row counts match across
layers, for example:

```python
spark.sql("""
    SELECT 'silver' AS layer, COUNT(*) FROM f1_workspace.silver.results
    UNION ALL SELECT 'gold', COUNT(*) FROM f1_workspace.gold.fact_results
""").show()
```

