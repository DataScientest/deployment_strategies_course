from fastapi.testclient import TestClient

from app import app


client = TestClient(app)


def test_health_returns_status_and_model_version():
    response = client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert "model_version" in body


def test_predict_returns_expected_shape():
    payload = {
        "amount": 1499.0,
        "merchant_category": "travel",
        "hour_of_day": 2,
        "country": "FR",
        "is_international": True,
        "device_risk_score": 0.91,
    }
    response = client.post("/predict", json=payload)
    assert response.status_code == 200
    body = response.json()
    assert set(body.keys()) == {"fraud_probability", "prediction", "model_version"}
    assert body["prediction"] in {"fraud", "legit"}


def test_metrics_endpoint_exposes_prometheus_text():
    response = client.get("/metrics")
    assert response.status_code == 200
    assert (
        "fraud_predictions_total" in response.text
        or "fraud_prediction_latency_seconds" in response.text
    )
