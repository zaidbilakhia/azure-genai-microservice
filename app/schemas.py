from pydantic import BaseModel, Field, field_validator


class AnalyzeRequest(BaseModel):
    text: str = Field(
        ...,
        min_length=5,
        description="Text to analyze. Must contain at least 5 characters.",
    )

    @field_validator("text")
    @classmethod
    def validate_text(cls, value: str) -> str:
        cleaned_text = value.strip()
        if len(cleaned_text) < 5:
            raise ValueError("Text must not be empty and must be at least 5 characters long.")
        return cleaned_text


class AnalyzeResponse(BaseModel):
    request_id: str
    summary: str
    category: str
    urgency: str
    recommended_action: str
    confidence: float = Field(..., ge=0.0, le=1.0)
