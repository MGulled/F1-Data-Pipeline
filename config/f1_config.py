import pyspark.sql.functions as F
CATALOG = "f1_workspace"
BRONZE_SCHEMA = "bronze"
SILVER_SCHEMA = "silver"
GOLD_SCHEMA = "gold"

STORAGE_ACCOUNT = "stf1project"
CONTAINER = "staging"
STAGING_BASE_PATH = f"abfss://{CONTAINER}@{STORAGE_ACCOUNT}.dfs.core.windows.net"

API_BASE_URL = "https://api.jolpi.ca/ergast/f1"

def add_ingestion_metadata(df):
  return (
    df
      .withColumn("ingestion_date", F.current_timestamp())
      .withColumn("source_file", F.col('_metadata.file_path'))
  )