#!/usr/bin/env bash
set -euo pipefail

AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-rg-azure-genai-microservice}"
AZURE_BACKEND_APP_NAME="${AZURE_BACKEND_APP_NAME:-ca-azure-genai-backend}"

if ! az containerapp show \
  --name "$AZURE_BACKEND_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" >/dev/null 2>&1; then
  echo "Container App not found. Deploy first with ./scripts/azure_deploy_backend.sh"
  exit 1
fi

FQDN="$(az containerapp show \
  --name "$AZURE_BACKEND_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query properties.configuration.ingress.fqdn \
  -o tsv)"

echo "Backend URL: https://${FQDN}"
echo "Health check: https://${FQDN}/"
echo "Analyze endpoint: https://${FQDN}/analyze"
echo "Local Streamlit command:"
echo "export BACKEND_URL=https://${FQDN}"
echo "streamlit run frontend/streamlit_app.py"
