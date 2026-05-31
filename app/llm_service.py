import json
import os
import time
from typing import Any

from dotenv import load_dotenv
from openai import OpenAI

from app.logger import get_logger

load_dotenv()

logger = get_logger(__name__)

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4o-mini")

REQUIRED_FIELDS = {
    "summary",
    "category",
    "urgency",
    "recommended_action",
    "confidence",
}
VALID_URGENCIES = {"low", "medium", "high"}

SYSTEM_PROMPT = """You are an AI assistant for analyzing customer or business text.
Return only valid JSON.
Do not include markdown.
Do not include explanations.
Do not include extra keys.
The JSON object must contain exactly these keys:
summary, category, urgency, recommended_action, confidence.
Urgency must be one of: low, medium, high.
Confidence must be a number between 0 and 1."""


def analyze_text(text: str, request_id: str | None = None) -> dict[str, Any]:
    """Analyze text with OpenAI and return validated structured JSON."""
    api_key = OPENAI_API_KEY
    model = OPENAI_MODEL
    log_request_id = request_id or "none"

    if not api_key:
        logger.error(
            'request_id=%s event=openai_config_error message="OPENAI_API_KEY is not configured"',
            log_request_id,
        )
        raise RuntimeError("OPENAI_API_KEY is not configured")

    client = OpenAI(api_key=api_key)
    user_prompt = f"Analyze this text and return structured JSON:\n{text}"

    logger.info(
        "request_id=%s event=llm_call_started model=%s input_length=%s",
        log_request_id,
        model,
        len(text),
    )
    start_time = time.perf_counter()

    try:
        response = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": user_prompt},
            ],
            temperature=0.2,
        )
    except Exception:
        duration_ms = (time.perf_counter() - start_time) * 1000
        logger.exception(
            "request_id=%s event=llm_call_completed model=%s success=false llm_latency_ms=%.2f",
            log_request_id,
            model,
            duration_ms,
        )
        raise

    duration_ms = (time.perf_counter() - start_time) * 1000
    usage = _extract_token_usage(response)
    logger.info(
        "request_id=%s event=llm_call_completed model=%s success=true llm_latency_ms=%.2f prompt_tokens=%s completion_tokens=%s total_tokens=%s",
        log_request_id,
        model,
        duration_ms,
        usage["prompt_tokens"],
        usage["completion_tokens"],
        usage["total_tokens"],
    )

    content = response.choices[0].message.content
    if not content:
        logger.warning("request_id=%s event=llm_empty_content", log_request_id)
        raise ValueError("LLM returned an empty response.")

    result = _parse_json_response(content, request_id=log_request_id)
    validated_result = _validate_analysis_output(result, request_id=log_request_id)
    logger.info(
        "request_id=%s event=llm_json_validation_succeeded model=%s",
        log_request_id,
        model,
    )
    validated_result["_metadata"] = {
        "model": model,
        "prompt_tokens": usage["prompt_tokens"],
        "completion_tokens": usage["completion_tokens"],
        "total_tokens": usage["total_tokens"],
        "llm_latency_ms": round(duration_ms, 2),
    }
    return validated_result


def _parse_json_response(content: str, request_id: str | None = None) -> dict[str, Any]:
    log_request_id = request_id or "none"
    try:
        result = json.loads(content)
    except json.JSONDecodeError as exc:
        logger.warning(
            'request_id=%s event=llm_json_parsing_failed error_type=JSONDecodeError message="%s"',
            log_request_id,
            exc,
        )
        raise ValueError("LLM returned invalid JSON.") from exc

    if not isinstance(result, dict):
        logger.warning("request_id=%s event=llm_json_not_object", log_request_id)
        raise ValueError("LLM output must be a JSON object.")

    return result


def _validate_analysis_output(data: dict[str, Any], request_id: str | None = None) -> dict[str, Any]:
    log_request_id = request_id or "none"
    if not isinstance(data, dict):
        logger.warning("request_id=%s event=llm_validation_failed reason=not_object", log_request_id)
        raise ValueError("LLM output must be a JSON object.")

    received_fields = set(data.keys())
    missing_fields = REQUIRED_FIELDS - received_fields
    extra_fields = received_fields - REQUIRED_FIELDS

    if missing_fields:
        fields = ", ".join(sorted(missing_fields))
        logger.warning(
            "request_id=%s event=llm_validation_failed missing_fields=%s",
            log_request_id,
            fields,
        )
        raise ValueError(f"LLM output is missing required fields: {fields}.")

    if extra_fields:
        fields = ", ".join(sorted(extra_fields))
        logger.warning(
            "request_id=%s event=llm_validation_failed extra_fields=%s",
            log_request_id,
            fields,
        )
        raise ValueError(f"LLM output included unexpected fields: {fields}.")

    urgency = data["urgency"]
    if urgency not in VALID_URGENCIES:
        logger.warning(
            "request_id=%s event=llm_validation_failed invalid_urgency=%s",
            log_request_id,
            urgency,
        )
        raise ValueError("LLM output urgency must be low, medium, or high.")

    confidence = data["confidence"]
    if isinstance(confidence, bool) or not isinstance(confidence, (int, float)):
        logger.warning(
            "request_id=%s event=llm_validation_failed reason=confidence_not_numeric",
            log_request_id,
        )
        raise ValueError("LLM output confidence must be a number between 0 and 1.")

    if not 0 <= confidence <= 1:
        logger.warning(
            "request_id=%s event=llm_validation_failed reason=confidence_out_of_range",
            log_request_id,
        )
        raise ValueError("LLM output confidence must be between 0 and 1.")

    data["confidence"] = float(confidence)
    return data


def _extract_token_usage(response: Any) -> dict[str, int | None]:
    usage = getattr(response, "usage", None)
    return {
        "prompt_tokens": getattr(usage, "prompt_tokens", None),
        "completion_tokens": getattr(usage, "completion_tokens", None),
        "total_tokens": getattr(usage, "total_tokens", None),
    }
