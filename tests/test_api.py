from fastapi.testclient import TestClient

from app.main import app


client = TestClient(app)


def test_health_check_returns_expected_message():
    response = client.get("/")

    assert response.status_code == 200
    assert response.json() == {"message": "Azure GenAI Microservice is running"}


def test_analyze_invalid_input_returns_422():
    response = client.post("/analyze", json={"text": "bad"})

    assert response.status_code == 422
    assert response.json()["detail"]["error"] == "ANALYSIS_ERROR"
    assert "request_id" in response.json()["detail"]


def test_analyze_success_without_real_openai_call(monkeypatch):
    def mock_analyze_text(text: str, request_id: str | None = None) -> dict:
        return {
            "summary": "Mock summary",
            "category": "Mock Category",
            "urgency": "medium",
            "recommended_action": "Mock action",
            "confidence": 0.88,
            "_metadata": {
                "model": "mock-model",
                "prompt_tokens": 10,
                "completion_tokens": 20,
                "total_tokens": 30,
                "llm_latency_ms": 123.45,
            },
        }

    monkeypatch.setattr("app.main.analyze_text", mock_analyze_text)

    response = client.post(
        "/analyze",
        json={"text": "This is a valid test message."},
    )
    body = response.json()

    assert response.status_code == 200
    assert "request_id" in body
    assert response.headers["X-Request-ID"] == body["request_id"]
    assert body["summary"] == "Mock summary"
    assert body["urgency"] == "medium"
    assert body["confidence"] == 0.88
