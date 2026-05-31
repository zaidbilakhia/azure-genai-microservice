#!/usr/bin/env bash
set -euo pipefail

AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-rg-azure-genai-microservice}"
AZURE_BACKEND_APP_NAME="${AZURE_BACKEND_APP_NAME:-ca-azure-genai-backend}"

echo "Showing logs for Container App: ${AZURE_BACKEND_APP_NAME}"
echo "Press CTRL+C to stop following logs."

az containerapp logs show \
  --name "$AZURE_BACKEND_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --follow
