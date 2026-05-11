import os
import time
import logging
import random
from typing import Literal

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from dotenv import load_dotenv
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from starlette.responses import Response

load_dotenv()

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("fraud_service")

MODEL_VERSION = os.getenv("MODEL_VERSION", "v1")

REQUEST_COUNT = Counter(
    "fraud_predictions_total",
    "Nombre total de prédictions",
    ["model_version", "prediction"],
)
REQUEST_LATENCY = Histogram(
    "fraud_prediction_latency_seconds",
    "Latence des prédictions",
    ["model_version"],
)
ERROR_COUNT = Counter(
    "fraud_prediction_errors_total",
    "Nombre total d'erreurs applicatives",
    ["model_version"],
)


class FraudRequest(BaseModel):
    amount: float = Field(ge=0)
    merchant_category: str
    hour_of_day: int = Field(ge=0, le=23)
    country: str
    is_international: bool
    device_risk_score: float = Field(ge=0, le=1)


class FraudResponse(BaseModel):
    fraud_probability: float
    prediction: Literal["fraud", "legit"]
    model_version: str


app = FastAPI(title="Fraud Scoring Service", version=MODEL_VERSION)


def score_request(payload: FraudRequest) -> float:
    score = 0.05
    if payload.amount > 1000:
        score += 0.35
    if payload.is_international:
        score += 0.20
    if payload.device_risk_score > 0.7:
        score += 0.30
    if payload.hour_of_day < 6:
        score += 0.10

    # TODO chapitre 2 : différencier plus clairement v1, v2 et v2-buggy.
    if MODEL_VERSION == "v2":
        score += 0.05
    if MODEL_VERSION == "v2-buggy":
        time.sleep(1.2)
        if random.random() < 0.35:
            raise HTTPException(status_code=500, detail="Bug simulé sur v2-buggy")

    return max(0.0, min(score, 0.99))


@app.post("/predict", response_model=FraudResponse)
def predict(payload: FraudRequest):
    started_at = time.perf_counter()
    try:
        probability = score_request(payload)
        prediction = "fraud" if probability >= 0.5 else "legit"
        REQUEST_COUNT.labels(model_version=MODEL_VERSION, prediction=prediction).inc()
        logger.info(
            "prediction served | model_version=%s | prediction=%s | amount=%s | country=%s",
            MODEL_VERSION,
            prediction,
            payload.amount,
            payload.country,
        )
        return FraudResponse(
            fraud_probability=round(probability, 4),
            prediction=prediction,
            model_version=MODEL_VERSION,
        )
    except Exception:
        ERROR_COUNT.labels(model_version=MODEL_VERSION).inc()
        raise
    finally:
        REQUEST_LATENCY.labels(model_version=MODEL_VERSION).observe(
            time.perf_counter() - started_at
        )


@app.get("/health")
def health():
    return {"status": "ok", "model_version": MODEL_VERSION}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
