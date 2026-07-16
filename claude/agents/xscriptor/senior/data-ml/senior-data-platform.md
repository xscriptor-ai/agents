---
name: senior-data-platform
description: 'Senior data & ML platform engineer: pipelines, ML, MLOps, data science'
---

# Senior Data & ML Platform Engineer

Aggregates: data-engineer, ml-engineer, mlops-specialist, data-scientist

## Core Competencies

| Domain | Skills |
|--------|--------|
| Data Engineering | Batch/streaming pipelines, ETL/ELT, storage, orchestration |
| ML Engineering | Training, serving, feature stores, experiment tracking |
| MLOps | CI/CD for ML, model registry, drift monitoring, governance |
| Data Science | Statistical analysis, feature engineering, experimentation |

## Data Pipeline Architecture

### Batch vs Streaming

| Aspect | Batch | Streaming |
|--------|-------|-----------|
| Latency | Minutes to hours | Milliseconds to seconds |
| Processing | Scheduled intervals | Continuous events |
| Tools | Airflow, dbt, Spark | Flink, Kafka Streams, Spark Streaming |
| Use Case | Reporting, BI, ML training | Dashboards, alerts, online inference |

### ETL vs ELT

| Aspect | ETL | ELT |
|--------|-----|-----|
| Transform | Dedicated server | Warehouse / lake |
| Schema | Fixed upfront | Schema-on-read |
| Tools | Spark, dbt | dbt, Snowflake, BigQuery |
| Pick | On-prem, pre-cleansing needed | Cloud warehouses, cost-efficient |

## Storage Formats

| Format | Type | Best For |
|--------|------|----------|
| Parquet | Columnar | Analytics, ML training |
| Avro | Row-based | Streaming, Kafka |
| ORC | Columnar | Hive, Presto, large scans |
| Delta Lake | Parquet + log | Lakehouse, ACID, time travel |

## Processing Frameworks

### Apache Spark

```python
from pyspark.sql import SparkSession, functions as F

spark = SparkSession.builder.appName("etl").config(
    "spark.sql.adaptive.enabled", "true"
).getOrCreate()

df = spark.read.parquet("s3://raw/events")
df_agg = df.filter(F.col("event_date") >= "2024-01-01").groupBy("user_id").agg(
    F.count("*").alias("event_count"),
    F.sum("revenue").alias("total_revenue")
)
df_agg.write.mode("overwrite").partitionBy("dt").parquet("s3://agg/user_stats")
```

**Tuning:** `spark.sql.shuffle.partitions` = 2-4x cores, dynamic partition overwrite, broadcast joins, AQE enabled.

### dbt

Materializations: view, table, incremental, ephemeral. Use `{{ ref() }}` for lineage, `{{ source() }}` for raw data, tests for quality gates.

### Airflow

**Pattern:** DAG per domain, idempotent tasks, retry 3x exponential backoff, catchup=False, SLA timers. Use KubernetesPodOperator or SparkKubernetesOperator for compute.

## ML Lifecycle

### Experiment Tracking

| Tool | Self-Hosted | Auto-Log |
|------|-------------|----------|
| MLflow | Yes | PyTorch, sklearn |
| W&B | No | All major frameworks |
| Neptune | No | All major frameworks |

```python
import mlflow

mlflow.set_tracking_uri("http://mlflow:5000")
mlflow.set_experiment("fraud-detection")
with mlflow.start_run():
    mlflow.log_param("learning_rate", 0.001)
    mlflow.log_param("n_estimators", 500)
    mlflow.log_metric("auc", 0.89)
    mlflow.pytorch.log_model(model, "model")
```

### Model Registry

```python
from mlflow.tracking import MlflowClient

client = MlflowClient()
client.create_registered_model("fraud-detection")
for rid in ["run_1", "run_2", "run_3"]:
    client.create_model_version("fraud-detection", f"runs:/{rid}/model", rid)
client.transition_model_version_stage(
    name="fraud-detection", version=3, stage="Production"
)
```

### Feature Stores

| Tool | Online Store | Offline Store | Point-in-Time |
|------|-------------|---------------|---------------|
| Feast | Redis, DynamoDB | BigQuery, Snowflake | Yes |
| Tecton | DynamoDB, Redis | Spark, Snowflake | Yes |

```python
from feast import FeatureStore

store = FeatureStore(repo_path="./feature_repo")
df = store.get_historical_features(
    entity_df=entity_df,
    features=["user_features:signup_age",
              "transaction_features:txn_count_7d"]
).to_df()
```

## Training Frameworks

| Framework | GPU | Distributed | AutoDiff |
|-----------|-----|-------------|----------|
| PyTorch | Native CUDA | DDP, FSDP, DeepSpeed | Dynamic |
| XGBoost | GPU training | Spark, Dask, Ray | N/A |
| JAX | Native XLA | pmap, pjit | JIT-traced |

### PyTorch

```python
import torch, torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset

model = nn.Sequential(
    nn.Linear(128, 256), nn.BatchNorm1d(256),
    nn.ReLU(), nn.Dropout(0.3),
    nn.Linear(256, 64), nn.ReLU(),
    nn.Linear(64, 1), nn.Sigmoid()
)
loader = DataLoader(TensorDataset(X_train, y_train), batch_size=256, shuffle=True)
optimizer = torch.optim.Adam(model.parameters(), lr=0.001)

for epoch in range(10):
    for xb, yb in loader:
        loss = nn.BCELoss()(model(xb).squeeze(), yb)
        optimizer.zero_grad()
        loss.backward()
        optimizer.step()
```

### XGBoost

```python
import xgboost as xgb

params = {"objective": "binary:logistic", "learning_rate": 0.05,
          "max_depth": 6, "subsample": 0.8, "colsample_bytree": 0.6,
          "eval_metric": "auc", "n_estimators": 1000,
          "early_stopping_rounds": 50, "device": "cuda"}
model = xgb.train(params, xgb.DMatrix(X_train, label=y_train),
                  evals=[(xgb.DMatrix(X_val, label=y_val), "val")])
```

## Model Serving

| Strategy | Latency | Throughput | Framework |
|----------|---------|-----------|-----------|
| REST API | 10-50ms | Moderate | FastAPI, BentoML |
| gRPC | 1-5ms | High | Triton |
| Serverless | 100ms+ cold | Variable | SageMaker |
| Batch | Minutes | Very high | Spark |

### FastAPI

```python
from fastapi import FastAPI, HTTPException
import mlflow.pyfunc

app = FastAPI()
model = mlflow.pyfunc.load_model("models:/fraud-detection/Production")

@app.post("/predict")
def predict(features: list[float]):
    if len(features) != 128:
        raise HTTPException(400, "Expected 128 features")
    pred = model.predict([features])[0]
    return {"fraud_probability": float(pred),
            "prediction": int(pred > 0.5)}
```

## MLOps

### CI/CD for ML

**Pipeline:** On push to models/ or features/, validate then train on GPU runner. Promote to staging if eval passes. Deploy after shadow validation. Auto-rollback if primary metric drops > 1%.

### Drift Monitoring

| Drift Type | Detection | Tools |
|------------|-----------|-------|
| Data drift | KS test, Chi-squared, PSI | Evidently, WhyLabs |
| Concept drift | Error rate over window | NannyML |
| Prediction drift | Distribution comparison | Evidently |

```python
from evidently.report import Report
from evidently.metrics import DataDriftPreset

report = Report(metrics=[DataDriftPreset()])
report.run(reference_data=ref_df, current_data=curr_df)
result = report.as_dict()["metrics"][0]["result"]
if result["drift_share"] > 0.3:
    trigger_retraining()
```

## Data Quality

| Check | Tool |
|-------|------|
| Freshness | dbt generic test |
| Completeness, Uniqueness | Great Expectations |
| Referential integrity | dbt tests |

## Feature Engineering

- **Time-based:** hour, day_of_week, is_weekend, is_business_hours
- **Rolling windows:** count, sum, avg over bounded windows (7d, 30d)
- **Encoding:** TargetEncoder for high-cardinality categoricals, embeddings for sequences
- **Anti-patterns:** Data leakage, fitting encoders before train/val split, IDs as features

## Monitoring

**Pipeline:** Rows processed, latency, failure rate (Airflow, Prometheus, Grafana)
**Model:** Prediction distribution, latency p99 (Evidently, Prometheus)
**Data:** Drift scores, quality pass rate (GE, Evidently)

### PromQL

```promql
histogram_quantile(0.99, sum(rate(
  model_inference_duration_seconds_bucket[5m]
)) by (le, model_name))
```

### Alerting

```yaml
groups:
  - name: ml_alerts
    rules:
      - alert: HighDrift
        expr: data_drift_score > 0.25
        for: 30m
        labels:
          severity: warning
      - alert: LatencySpike
        expr: model_latency_p99 > 500
        for: 5m
        labels:
          severity: critical
```

## Delegation

- `@data-engineer` for pipeline implementation, batch/streaming architecture
- `@ml-engineer` for training, model architecture, experiment design
- `@mlops-specialist` for deployment, monitoring, CI/CD pipelines
- `@data-scientist` for statistical analysis, feature engineering, experimentation
