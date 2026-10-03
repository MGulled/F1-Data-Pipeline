# F1 Data Engineering Pipeline

An end-to-end batch data pipeline that pulls Formula 1 race data from the public
[Jolpica-F1 API](https://github.com/jolpica/jolpica-f1) and transforms it through a
bronze/silver/gold medallion architecture on Databricks, orchestrated as a scheduled
Databricks Job and provisioned entirely with Terraform.

This is my third portfolio project, built to show a different orchestration pattern
than my [Olist ecommerce project](#) (which uses Databricks Lakeflow Declarative
Pipelines and dbt). Here, bronze/silver/gold are built as plain PySpark notebooks,
orchestrated with explicit task dependencies in a Databricks Job, with Terraform
managing the infrastructure instead of Databricks Asset Bundles.

## Architecture

```mermaid
flowchart LR
    API[Jolpica-F1 API] -->|paginated requests| ADLS[(ADLS Gen2\nstaging container)]
    ADLS --> Bronze[Bronze\nnested, schema-enforced]
    Bronze --> Silver[Silver\nflattened, typed, cleaned]
    Silver --> Gold[Gold\nstar schema]

    subgraph Gold Layer
        DimDrivers[dim_drivers]
        DimConstructors[dim_constructors]
        DimCircuits[dim_circuits]
        DimRaces[dim_races]
        FactResults[fact_results]
        DimDrivers --> FactResults
        DimConstructors --> FactResults
        DimRaces --> FactResults
    end

    Gold --> PowerBI[Power BI\n(planned)]
```

## Data source

[Jolpica-F1](https://github.com/jolpica/jolpica-f1) is a community-maintained,
Ergast-compatible REST API for Formula 1 historical and current-season data. Five
endpoints are pulled: `circuits`, `constructors`, `drivers`, `races`, and `results`.
All requests are paginated (`limit`/`offset`) against the API's reported `total`,
since the default page size is only 30 rows.

## Layering rules

| Layer | Rule |
|---|---|
| **Bronze** | Mirrors the raw API JSON shape exactly, including nested structs (`Driver`, `Constructor`, `FastestLap`, `Location`). Schema is explicitly declared with `StructType`, not inferred, so a missing or renamed field fails loudly instead of silently returning nulls. No joins, no flattening. |
| **Silver** | One notebook per bronze table. Flattens nested structs into top-level columns, trims whitespace, title-cases display text, and casts every field to its correct type (dates, ints, doubles). No cross-table joins at this layer — each table is cleaned independently. |
| **Gold** | Builds a star schema: `dim_drivers`, `dim_constructors`, `dim_circuits`, `dim_races`, and `fact_results`. This is the only layer where tables are joined against each other. Dimension tables hold descriptive attributes; the fact table holds only foreign keys and race-result measures (grid, position, points, status), joined against the dimensions as a referential integrity check. |

## Orchestration

A single Databricks Job (`f1_pipeline`) runs all 15 notebooks with explicit task
dependencies — each silver task depends on its own bronze task, each gold dimension
depends on its silver source(s), and `fact_results` depends on every dimension plus
silver results.

![Job task graph](docs/job_graph.png)

The job runs weekly, Mondays at 08:00 Europe/Oslo, after the Sunday race's results are
available. Bronze, silver, and gold all write with `overwrite` rather than `append`,
since each run pulls the complete current season — appending would duplicate every
race already loaded. A failure notification is configured on the job, and the
ingestion tasks have one automatic retry to absorb a brief API hiccup.

## Infrastructure (Terraform)

Everything is provisioned as code in [`terraform/`](terraform/):

- Resource group, ADLS Gen2 storage account and staging container
- Databricks workspace
- Unity Catalog catalog (`f1_workspace`) and three schemas (`bronze`, `silver`, `gold`)
- The full Databricks Job, including the task graph, schedule, and notifications

Remote state is stored in a separate Azure storage account (`stf1tfstate`), configured
via the `azurerm` backend in `backend.tf`.

## Design decisions

- **Notebooks + Jobs over Lakeflow.** My Olist project already demonstrates Lakeflow
  Declarative Pipelines and dbt. This project uses hand-written PySpark transforms and
  explicit task orchestration instead, to show that pattern as well.
- **PySpark joins over dbt for gold.** Same reasoning — dbt is already proven
  elsewhere in my portfolio. The star schema here is built with plain DataFrame joins.
- **Bronze stays nested.** Keeping the raw struct shape at bronze (rather than
  flattening immediately) means bronze remains a faithful, re-derivable archive of
  what the API actually returned, independent of any transformation decisions made
  later.
- **No SCD Type 2.** Driver and constructor attributes in this dataset barely change
  season to season, and the Jolpica drivers endpoint doesn't expose team history
  directly (that only shows up per-result). SCD Type 2 would have been the right tool
  if team-change history were a requirement, but it wasn't a good fit for what this
  data actually models, so I kept dimension tables as straightforward overwrites.

## Known issues and what I'd do differently

Documenting these honestly, since working through them was most of the actual
engineering effort:

- **Driver pagination cap.** The drivers bronze pull initially had no pagination and
  silently returned only the API's default 30 rows. This caused the gold `fact_results`
  table to drop 15 result rows via inner join, since those drivers' foreign keys
  didn't exist in `dim_drivers`. Fixed by paginating the drivers pull the same way as
  results.
- **Missing `season` field.** An early version of the results schema and extraction
  logic never tagged each result with its season, which only became a problem once a
  composite key (`Season` + `Round` + `Driver_Id`) was needed to uniquely identify a
  result. Fixed upstream, in the pagination step, rather than patched downstream.
- **Append-mode duplication.** Early runs of the Databricks Job used `append` for the
  results tables across all three layers. Since each run pulls the *entire* current
  season rather than just new rows, this duplicated every race on each run. Switched
  to `overwrite` throughout, since the API is queried fresh each time rather than
  incrementally.
- **If I rebuilt this today**, I'd add row-count and null-check data quality
  validation as its own step before each write, rather than relying on manual
  `.count()` checks during development.

## Tech stack

Azure (ADLS Gen2, Databricks) · PySpark · Delta Lake · Databricks Jobs · Terraform ·
Jolpica-F1 REST API
