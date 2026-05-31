#!/usr/bin/env bash
set -euo pipefail

AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-rg-azure-genai-microservice}"
AZURE_CONTAINER_REGISTRY="${AZURE_CONTAINER_REGISTRY:-acrgenaimicroservice}"
AZURE_CONTAINER_APP_ENV="${AZURE_CONTAINER_APP_ENV:-cae-azure-genai-microservice}"
AZURE_BACKEND_APP_NAME="${AZURE_BACKEND_APP_NAME:-ca-azure-genai-backend}"
AZURE_BACKEND_IMAGE_NAME="${AZURE_BACKEND_IMAGE_NAME:-azure-genai-backend}"
OPENAI_MODEL="${OPENAI_MODEL:-gpt-4o-mini}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"

echo "Checking Azure login..."
if ! az account show >/dev/null 2>&1; then
  echo "Please login first with: az login"
  exit 1
fi

if ! docker ps >/dev/null 2>&1; then
  echo "Docker is not running or permission is denied. Try: sudo systemctl start docker && newgrp docker"
  exit 1
fi

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  echo "OPENAI_API_KEY is required. Export it before running this script."
  exit 1
fi

echo "Reading ACR login server..."
ACR_LOGIN_SERVER="$(az acr show \
  --name "$AZURE_CONTAINER_REGISTRY" \
  --query loginServer \
  -o tsv)"

echo "Logging in to Azure Container Registry..."
az acr login --name "$AZURE_CONTAINER_REGISTRY"

IMAGE_TAG="$(date +%Y%m%d%H%M%S)"
IMAGE_URI="${ACR_LOGIN_SERVER}/${AZURE_BACKEND_IMAGE_NAME}:${IMAGE_TAG}"
LATEST_URI="${ACR_LOGIN_SERVER}/${AZURE_BACKEND_IMAGE_NAME}:latest"

echo "Building backend Docker image: ${IMAGE_URI}"
docker build -f Dockerfile.backend -t "$IMAGE_URI" -t "$LATEST_URI" .

echo "Pushing backend Docker image tags..."
docker push "$IMAGE_URI"
docker push "$LATEST_URI"

echo "Reading ACR credentials for Container App registry access..."
ACR_USERNAME="$(az acr credential show \
  --name "$AZURE_CONTAINER_REGISTRY" \
  --query username \
  -o tsv)"

ACR_PASSWORD="$(az acr credential show \
  --name "$AZURE_CONTAINER_REGISTRY" \
  --query "passwords[0].value" \
  -o tsv)"

if az containerapp show \
  --name "$AZURE_BACKEND_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" >/dev/null 2>&1; then
  echo "Container App exists. Updating backend app: ${AZURE_BACKEND_APP_NAME}"
  az containerapp secret set \
    --name "$AZURE_BACKEND_APP_NAME" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --secrets openai-api-key="$OPENAI_API_KEY"

  az containerapp update \
    --name "$AZURE_BACKEND_APP_NAME" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --image "$IMAGE_URI" \
    --set-env-vars OPENAI_API_KEY=secretref:openai-api-key OPENAI_MODEL="$OPENAI_MODEL" LOG_LEVEL="$LOG_LEVEL"
else
  echo "Creating backend Container App: ${AZURE_BACKEND_APP_NAME}"
  az containerapp create \
    --name "$AZURE_BACKEND_APP_NAME" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --environment "$AZURE_CONTAINER_APP_ENV" \
    --image "$IMAGE_URI" \
    --registry-server "$ACR_LOGIN_SERVER" \
    --registry-username "$ACR_USERNAME" \
    --registry-password "$ACR_PASSWORD" \
    --target-port 8000 \
    --ingress external \
    --secrets openai-api-key="$OPENAI_API_KEY" \
    --env-vars OPENAI_API_KEY=secretref:openai-api-key OPENAI_MODEL="$OPENAI_MODEL" LOG_LEVEL="$LOG_LEVEL"
fi

FQDN="$(az containerapp show \
  --name "$AZURE_BACKEND_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query properties.configuration.ingress.fqdn \
  -o tsv)"

echo "Backend deployed successfully."
echo "Backend URL: https://${FQDN}"
echo "Health: https://${FQDN}/"
echo "Analyze: https://${FQDN}/analyze"
echo "Next command: ./scripts/azure_test_backend.sh \"https://${FQDN}\""
