#!/usr/bin/env bash
set -euo pipefail

AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-rg-azure-genai-microservice}"
AZURE_BACKEND_APP_NAME="${AZURE_BACKEND_APP_NAME:-ca-azure-genai-backend}"
BACKEND_URL="${1:-}"

if [[ -z "$BACKEND_URL" ]]; then
  echo "No backend URL provided. Reading URL from Azure Container Apps..."
  FQDN="$(az containerapp show \
    --name "$AZURE_BACKEND_APP_NAME" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --query properties.configuration.ingress.fqdn \
    -o tsv)"
  BACKEND_URL="https://${FQDN}"
fi

BACKEND_URL="${BACKEND_URL%/}"

print_json() {
  if command -v jq >/dev/null 2>&1; then
    jq .
  else
    cat
    printf '\n'
  fi
}

echo "Testing health endpoint: ${BACKEND_URL}/"
curl -sS "${BACKEND_URL}/" | print_json

echo "Testing analyze endpoint: ${BACKEND_URL}/analyze"
curl -sS -X POST "${BACKEND_URL}/analyze" \
  -H "Content-Type: application/json" \
  -d '{"text": "The customer is frustrated because the payment failed twice and they need urgent help."}' | print_json
