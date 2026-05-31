#!/usr/bin/env bash
set -euo pipefail

AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-rg-azure-genai-microservice}"
AZURE_BACKEND_APP_NAME="${AZURE_BACKEND_APP_NAME:-ca-azure-genai-backend}"
OPENAI_MODEL="${OPENAI_MODEL:-gpt-4o-mini}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  echo "OPENAI_API_KEY is required. Export it before running this script."
  exit 1
fi

if ! az containerapp show \
  --name "$AZURE_BACKEND_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" >/dev/null 2>&1; then
  echo "Container App not found. Deploy first with ./scripts/azure_deploy_backend.sh"
  exit 1
fi

echo "Updating OpenAI API key secret for Container App: ${AZURE_BACKEND_APP_NAME}"
az containerapp secret set \
  --name "$AZURE_BACKEND_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --secrets openai-api-key="$OPENAI_API_KEY"

echo "Updating backend environment variables..."
az containerapp update \
  --name "$AZURE_BACKEND_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --set-env-vars OPENAI_API_KEY=secretref:openai-api-key OPENAI_MODEL="$OPENAI_MODEL" LOG_LEVEL="$LOG_LEVEL"

echo "Secrets updated. Restarting or new revision may be needed if changes do not appear immediately."
echo "Inspect revisions with:"
echo "az containerapp revision list --name \"$AZURE_BACKEND_APP_NAME\" --resource-group \"$AZURE_RESOURCE_GROUP\" -o table"
