#!/usr/bin/env bash
set -euo pipefail

AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-rg-azure-genai-microservice}"
AZURE_LOCATION="${AZURE_LOCATION:-westeurope}"
AZURE_CONTAINER_REGISTRY="${AZURE_CONTAINER_REGISTRY:-acrgenaimicroservice}"
AZURE_CONTAINER_APP_ENV="${AZURE_CONTAINER_APP_ENV:-cae-azure-genai-microservice}"
AZURE_BACKEND_APP_NAME="${AZURE_BACKEND_APP_NAME:-ca-azure-genai-backend}"
LOG_WORKSPACE_NAME="log-${AZURE_BACKEND_APP_NAME}"

echo "Checking Azure login..."
if ! az account show >/dev/null 2>&1; then
  echo "Please login first with: az login"
  exit 1
fi

echo "Creating resource group if needed: ${AZURE_RESOURCE_GROUP}"
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

echo "Azure infrastructure is ready."
echo "Resource group: ${AZURE_RESOURCE_GROUP}"
echo "Location: ${AZURE_LOCATION}"
echo "Container registry: ${AZURE_CONTAINER_REGISTRY}"
echo "Container Apps environment: ${AZURE_CONTAINER_APP_ENV}"
echo "Next command: ./scripts/azure_deploy_backend.sh"
