import os

import requests
import streamlit as st
from dotenv import load_dotenv

load_dotenv()

BACKEND_URL = os.getenv("BACKEND_URL", "http://127.0.0.1:8000").rstrip("/")
EXAMPLE_TEXT = (
    "Hi, I ordered a laptop 2 weeks ago but it still has not arrived. "
    "I already paid, and I need it urgently for my work. "
    "Please check the status or refund me."
)


def analyze_text(text: str) -> dict:
    response = requests.post(
        f"{BACKEND_URL}/analyze",
        json={"text": text},
        timeout=60,
    )
    response.raise_for_status()
    return response.json()


st.set_page_config(page_title="Azure AI Microservice", page_icon="AI")

st.title("Azure AI Microservice")
st.caption("Analyze customer/business text using a GenAI backend.")

with st.expander("Debug info"):
    st.write(f"Backend URL: `{BACKEND_URL}`")

st.text_area("Example text", value=EXAMPLE_TEXT, height=120, disabled=True)

text = st.text_area("Text to analyze", height=180, placeholder="Paste customer or business text here...")

if st.button("Analyze", type="primary"):
    cleaned_text = text.strip()

    if len(cleaned_text) < 5:
        st.error("Please enter at least 5 characters.")
    else:
        try:
            with st.spinner("Analyzing text..."):
                result = analyze_text(cleaned_text)
        except requests.exceptions.ConnectionError:
            st.error(
                "Backend is not running. Please start FastAPI with uvicorn app.main:app --reload"
            )
        except requests.exceptions.Timeout:
            st.error("The backend took too long to respond. Please try again.")
        except requests.exceptions.HTTPError as exc:
            try:
                error_body = exc.response.json()
                message = error_body.get("detail", {}).get("message", "Backend returned an error.")
            except ValueError:
                message = "Backend returned an error."
            st.error(message)
        except requests.exceptions.RequestException:
            st.error("Could not reach the backend. Please check the backend URL and try again.")
        else:
            urgency = result.get("urgency", "").lower()

            st.subheader("Analysis Result")
            st.write(f"Request ID: `{result.get('request_id', 'unknown')}`")

            if urgency == "high":
                st.error("High priority")
            elif urgency == "medium":
                st.warning("Medium priority")
            else:
                st.success("Low priority")

            st.metric("Confidence", f"{result.get('confidence', 0) * 100:.0f}%")
            st.write(f"Summary: {result.get('summary', '')}")
            st.write(f"Category: {result.get('category', '')}")
            st.write(f"Urgency: {result.get('urgency', '')}")
            st.write(f"Recommended Action: {result.get('recommended_action', '')}")
