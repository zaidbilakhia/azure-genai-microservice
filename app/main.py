import time
import uuid

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app.logger import get_logger
from app.llm_service import analyze_text
from app.schemas import AnalyzeRequest, AnalyzeResponse

app = FastAPI(title="Azure GenAI Microservice")
logger = get_logger(__name__)


def error_detail(request_id: str, error_code: str, message: str) -> dict[str, str]:
    return {"request_id": request_id, "error": error_code, "message": message}


@app.middleware("http")
async def log_requests(request: Request, call_next):
    start_time = time.perf_counter()
    method = request.method
    path = request.url.path
    request_id = str(uuid.uuid4())
    request.state.request_id = request_id

    logger.info(
        "request_id=%s event=request_started method=%s path=%s",
        request_id,
        method,
        path,
    )

    try:
        response = await call_next(request)
    except Exception:
        duration_ms = (time.perf_counter() - start_time) * 1000
        logger.exception(
            "request_id=%s event=request_failed method=%s path=%s duration_ms=%.2f",
            request_id,
            method,
            path,
            duration_ms,
        )
        return JSONResponse(
            status_code=500,
            headers={"X-Request-ID": request_id},
            content={
                "detail": error_detail(
                    request_id,
                    "INTERNAL_SERVER_ERROR",
                    "Internal server error",
                )
            },
        )

    duration_ms = (time.perf_counter() - start_time) * 1000
    response.headers["X-Request-ID"] = request_id
    logger.info(
        "request_id=%s event=request_completed method=%s path=%s status_code=%s duration_ms=%.2f",
        request_id,
        method,
        path,
        response.status_code,
        duration_ms,
    )

    return response


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    request_id = getattr(request.state, "request_id", "unknown")
    logger.warning(
        "request_id=%s event=request_validation_failed method=%s path=%s errors=%s",
        request_id,
        request.method,
        request.url.path,
        len(exc.errors()),
    )
    return JSONResponse(
        status_code=422,
        content={
            "detail": error_detail(
                request_id,
                "ANALYSIS_ERROR",
                "Invalid request body",
            )
        },
    )


@app.get("/")
def health_check() -> dict[str, str]:
    return {"message": "Azure GenAI Microservice is running"}


@app.post("/analyze", response_model=AnalyzeResponse)
def analyze(request: AnalyzeRequest, fastapi_request: Request) -> AnalyzeResponse:
    request_id = getattr(fastapi_request.state, "request_id", "unknown")
    try:
        logger.info(
            "request_id=%s event=analysis_started input_length=%s",
            request_id,
            len(request.text),
        )
        analysis_result = analyze_text(request.text, request_id=request_id)
        metadata = analysis_result.pop("_metadata", {})
        logger.info(
            'request_id=%s event=analysis_completed category="%s" urgency=%s confidence=%s model=%s total_tokens=%s llm_latency_ms=%s',
            request_id,
            analysis_result.get("category"),
            analysis_result.get("urgency"),
            analysis_result.get("confidence"),
            metadata.get("model"),
            metadata.get("total_tokens"),
            metadata.get("llm_latency_ms"),
        )
        return AnalyzeResponse(request_id=request_id, **analysis_result)
    except ValueError as exc:
        logger.warning(
            'request_id=%s event=analysis_failed error_type=ValueError message="LLM returned invalid structured output"',
            request_id,
        )
        raise HTTPException(
            status_code=502,
            detail=error_detail(
                request_id,
                "LLM_OUTPUT_ERROR",
                "LLM returned invalid structured output",
            ),
        ) from exc
    except RuntimeError as exc:
        if "OPENAI_API_KEY is not configured" in str(exc):
            logger.error(
                'request_id=%s event=analysis_failed error_type=RuntimeError message="OPENAI_API_KEY is not configured"',
                request_id,
            )
            raise HTTPException(
                status_code=500,
                detail=error_detail(
                    request_id,
                    "CONFIG_ERROR",
                    "OPENAI_API_KEY is not configured",
                ),
            ) from exc
        logger.exception(
            'request_id=%s event=analysis_failed error_type=RuntimeError message="Internal server error while analyzing text"',
            request_id,
        )
        raise HTTPException(
            status_code=500,
            detail=error_detail(
                request_id,
                "ANALYSIS_ERROR",
                "Internal server error while analyzing text",
            ),
        ) from exc
    except Exception as exc:
        logger.exception(
            'request_id=%s event=analysis_failed error_type=%s message="Internal server error while analyzing text"',
            request_id,
            type(exc).__name__,
        )
        raise HTTPException(
            status_code=500,
            detail=error_detail(
                request_id,
                "ANALYSIS_ERROR",
                "Internal server error while analyzing text",
            ),
        ) from exc
