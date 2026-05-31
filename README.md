# Azure GenAI Microservice

A FastAPI backend and Streamlit frontend for analyzing customer/business text with a real OpenAI LLM. The backend returns strict structured JSON, tracks each request with a `request_id`, and logs latency, model, and token usage locally.

This project uses the OpenAI API, not Azure OpenAI.

## Milestone 4: Streamlit UI + Request ID + Token Usage + Structured Logs

- FastAPI handles `POST /analyze`.
- Streamlit sends text to the FastAPI backend.
- Each request gets a unique `request_id`.
- The `request_id` is returned in the API response body and `X-Request-ID` response header.
- Token usage is collected from the OpenAI API response when available.
- Structured logs include `request_id`, endpoint, method, status, latency, model, token usage, urgency, category, and confidence.
- Logs do not include the OpenAI API key, full user input text, or raw LLM response.

## Milestone 5: Dockerized Local Deployment

Docker packages the FastAPI backend and Streamlit frontend so they run the same way across local environments. Docker Compose starts both services together.

- Backend runs on port `8000`.
- Frontend runs on port `8501`.
- In Docker Compose, the frontend talks to the backend using the Docker service name: `http://backend:8000`.
- The project still uses the OpenAI API, not Azure OpenAI.

## Milestone 6: GitHub CI Pipeline

GitHub Actions checks the project automatically when code is pushed to `main` or opened as a pull request.

- CI runs Python compile checks.
- CI runs FastAPI tests.
- CI validates the Docker Compose configuration.
- CI builds the backend Docker image.
- CI builds the frontend Docker image.
- CI does not call OpenAI.
- CI does not need `OPENAI_API_KEY`.

## Setup

1. Create and activate a virtual environment:

```bash
python -m venv .venv
source .venv/bin/activate
```

2. Install dependencies:

```bash
pip install -r requirements.txt
```

3. Create a local `.env` file from the example:

```bash
cp .env.example .env
```

4. Set your OpenAI API key as an environment variable:

```bash
export OPENAI_API_KEY=your_openai_api_key_here
```

Or set it in `.env` for local development:

```bash
OPENAI_API_KEY=your_openai_api_key_here
OPENAI_MODEL=gpt-4o-mini
LOG_LEVEL=INFO
BACKEND_URL=http://127.0.0.1:8000
```

`OPENAI_MODEL` is optional and defaults to `gpt-4o-mini`.
`LOG_LEVEL` is optional and defaults to `INFO`.
`BACKEND_URL` is used by the Streamlit frontend and defaults to `http://127.0.0.1:8000`.

## Run Locally

Start the FastAPI backend:

```bash
uvicorn app.main:app --reload
```

Start the Streamlit frontend in another terminal:

```bash
streamlit run frontend/streamlit_app.py
```

Open the frontend:

```text
http://localhost:8501
```

## Run With Docker Compose

You can pass your OpenAI key with an exported environment variable:

```bash
export OPENAI_API_KEY=your_openai_api_key_here
docker compose up --build
```

Or create a local `.env` file:

```bash
OPENAI_API_KEY=your_openai_api_key_here
OPENAI_MODEL=gpt-4o-mini
LOG_LEVEL=INFO
```

Then start both containers:

```bash
docker compose up --build
```

Stop containers:

```bash
docker compose down
```

Open the frontend:

```text
http://localhost:8501
```

The backend is available at:

```text
http://127.0.0.1:8000
```

## Run Individual Docker Containers

Run backend only:

```bash
docker build -f Dockerfile.backend -t azure-genai-backend .
docker run --env-file .env -p 8000:8000 azure-genai-backend
```

Run frontend only, pointing it at a backend running on your host machine:

```bash
docker build -f Dockerfile.frontend -t azure-genai-frontend .
docker run -e BACKEND_URL=http://host.docker.internal:8000 -p 8501:8501 azure-genai-frontend
```

## Local Checks

Run tests locally:

```bash
pytest -q
```

Run compile checks:

```bash
python3 -m compileall app
python3 -m py_compile frontend/streamlit_app.py
```

Validate Docker Compose:

```bash
docker compose config
```

Build Docker images:

```bash
docker build -f Dockerfile.backend -t azure-genai-backend:test .
docker build -f Dockerfile.frontend -t azure-genai-frontend:test .
```

## GitHub Setup

Initialize the repository and push it to GitHub:

```bash
git init
git add .
git commit -m "Initial Azure AI Microservice with FastAPI, Streamlit, Docker, and CI"
git branch -M main
git remote add origin <your-github-repo-url>
git push -u origin main
```

Never commit `.env`. Add secrets later only when deployment is added. For now, CI does not need secrets.

## Test Backend Directly

Health check:

```bash
curl http://127.0.0.1:8000/
```

Analyze text:

```bash
curl -X POST "http://127.0.0.1:8000/analyze" \
  -H "Content-Type: application/json" \
  -d '{"text": "The customer is frustrated because the payment failed twice and they need urgent help."}'
```

Example success response:

```json
{
  "request_id": "some-uuid",
  "summary": "The customer is frustrated because two payment attempts failed and they need urgent help.",
  "category": "Payment Issue",
  "urgency": "high",
  "recommended_action": "Contact the customer quickly and investigate the failed payment attempts.",
  "confidence": 0.9
}
```

Invalid input test:

```bash
curl -X POST "http://127.0.0.1:8000/analyze" \
  -H "Content-Type: application/json" \
  -d '{"text": "bad"}'
```

Example error response:

```json
{
  "detail": {
    "request_id": "some-uuid",
    "error": "ANALYSIS_ERROR",
    "message": "Invalid request body"
  }
}
```

## Docker Troubleshooting

- If `OPENAI_API_KEY` is missing, make sure it is exported in your shell or placed in a local `.env` file.
- If the frontend cannot reach the backend in Docker Compose, check that `BACKEND_URL=http://backend:8000` is set for the frontend service.
- If a port is already in use, stop previous `uvicorn`, `streamlit`, or Docker processes using ports `8000` or `8501`.
- Do not commit `.env`; it is ignored by Git and excluded from Docker builds.

## Example Logs

```text
2026-05-26 12:30:10 | INFO | app.main | request_id=some-uuid event=request_started method=POST path=/analyze
2026-05-26 12:30:10 | INFO | app.main | request_id=some-uuid event=analysis_started input_length=86
2026-05-26 12:30:10 | INFO | app.llm_service | request_id=some-uuid event=llm_call_started model=gpt-4o-mini input_length=86
2026-05-26 12:30:12 | INFO | app.llm_service | request_id=some-uuid event=llm_call_completed model=gpt-4o-mini success=true llm_latency_ms=2295.28 prompt_tokens=92 completion_tokens=68 total_tokens=160
2026-05-26 12:30:12 | INFO | app.llm_service | request_id=some-uuid event=llm_json_validation_succeeded model=gpt-4o-mini
2026-05-26 12:30:12 | INFO | app.main | request_id=some-uuid event=analysis_completed category="Payment Issue" urgency=high confidence=0.9 model=gpt-4o-mini total_tokens=160 llm_latency_ms=2295.28
2026-05-26 12:30:12 | INFO | app.main | request_id=some-uuid event=request_completed method=POST path=/analyze status_code=200 duration_ms=2360.94
```
