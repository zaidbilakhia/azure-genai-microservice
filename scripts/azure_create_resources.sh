#!/usr/bin/env bash
set -euo pipefail

AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-rg-azure-genai-microservice}"
AZURE_LOCATION="${AZURE_LOCATION:-westeurope}"
AZURE_CONTAINER_REGISTRY="${AZURE_CONTAINER_REGISTRY:-acrgenaimicroservice}"
AZURE_CONTAINER_APP_ENV="${AZURE_CONTAINER_APP_ENV:-cae-azure-genai-microservice}"
AZURE_BACKEND_APP_NAME="${AZURE_BACKEND_APP_NAME:-ca-azure-genai-backend}"
AZURE_BACKEND_IMAGE_NAME="${AZURE_BACKEND_IMAGE_NAME:-azure-genai-backend}"
OPENAI_MODEL="${OPENAI_MODEL:-gpt-4o-mini}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_WORKSPACE_NAME="log-${AZURE_BACKEND_APP_NAME}"

echo "Checking Azure login..."
if ! az account show >/dev/null 2>&1; then
  echo "Please login first with: az login"
  exit 1
fi

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  echo "OPENAI_API_KEY is required. Export it before running this script."
  exit 1
fi

echo "Creating resource group: ${AZURE_RESOURCE_GROUP}"
az group create \
  --name "$AZURE_RESOURCE_GROUP" \
  --location "$AZURE_LOCATION"

echo "Creating Azure Container Registry if needed: ${AZURE_CONTAINER_REGISTRY}"
if ! az acr show --name "$AZURE_CONTAINER_REGISTRY" --resource-group "$AZURE_RESOURCE_GROUP" >/dev/null 2>&1; then
  az acr create \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --name "$AZURE_CONTAINER_REGISTRY" \
    --sku Basic \
    --admin-enabled true
else
  echo "Azure Container Registry already exists."
fi

echo "Creating Log Analytics workspace if needed: ${LOG_WORKSPACE_NAME}"
if ! az monitor log-analytics workspace show \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --workspace-name "$LOG_WORKSPACE_NAME" >/dev/null 2>&1; then
  az monitor log-analytics workspace create \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --workspace-name "$LOG_WORKSPACE_NAME" \
    --location "$AZURE_LOCATION"
else
  echo "Log Analytics workspace already exists."
fi

echo "Reading Log Analytics workspace configuration..."
WORKSPACE_ID="$(az monitor log-analytics workspace show \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --workspace-name "$LOG_WORKSPACE_NAME" \
  --query customerId \
  -o tsv)"

WORKSPACE_KEY="$(az monitor log-analytics workspace get-shared-keys \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --workspace-name "$LOG_WORKSPACE_NAME" \
  --query primarySharedKey \
  -o tsv)"

echo "Creating Azure Container Apps environment if needed: ${AZURE_CONTAINER_APP_ENV}"
if ! az containerapp env show \
  --name "$AZURE_CONTAINER_APP_ENV" \
  --resource-group "$AZURE_RESOURCE_GROUP" >/dev/null 2>&1; then
  az containerapp env create \
    --name "$AZURE_CONTAINER_APP_ENV" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --location "$AZURE_LOCATION" \
    --logs-workspace-id "$WORKSPACE_ID" \
    --logs-workspace-key "$WORKSPACE_KEY"
else
  echo "Azure Container Apps environment already exists."
fi

echo "Logging in to Azure Container Registry..."
az acr login --name "$AZURE_CONTAINER_REGISTRY"

ACR_LOGIN_SERVER="$(az acr show \
  --name "$AZURE_CONTAINER_REGISTRY" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query loginServer \
  -o tsv)"

IMAGE="${ACR_LOGIN_SERVER}/${AZURE_BACKEND_IMAGE_NAME}:latest"

echo "Building backend Docker image: ${IMAGE}"
docker build -f Dockerfile.backend -t "$IMAGE" .

echo "Pushing backend Docker image to ACR..."
docker push "$IMAGE"

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
    --image "$IMAGE" \
    --set-env-vars OPENAI_API_KEY=secretref:openai-api-key OPENAI_MODEL="$OPENAI_MODEL" LOG_LEVEL="$LOG_LEVEL"
else
  echo "Creating backend Container App: ${AZURE_BACKEND_APP_NAME}"
  az containerapp create \
    --name "$AZURE_BACKEND_APP_NAME" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --environment "$AZURE_CONTAINER_APP_ENV" \
    --image "$IMAGE" \
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

echo "Backend deployed successfully:"
echo "https://${FQDN}"
