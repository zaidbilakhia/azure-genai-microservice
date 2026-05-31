#!/usr/bin/env bash
set -euo pipefail

AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-rg-azure-genai-microservice}"
AZURE_LOCATION="${AZURE_LOCATION:-westeurope}"
AZURE_CONTAINER_REGISTRY="${AZURE_CONTAINER_REGISTRY:-acrgenaimicroservice}"
AZURE_BACKEND_APP_NAME="${AZURE_BACKEND_APP_NAME:-ca-azure-genai-backend}"
AZURE_BACKEND_IMAGE_NAME="${AZURE_BACKEND_IMAGE_NAME:-azure-genai-backend}"

for tool in az docker curl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required tool not found: ${tool}"
    exit 1
  fi
done

if ! az account show >/dev/null 2>&1; then
  echo "Not logged in to Azure. Run: az login"
  exit 1
fi

if ! docker ps >/dev/null 2>&1; then
  echo "Docker is not running or permission is denied. Try: sudo systemctl start docker && newgrp docker"
  exit 1
fi

if az extension show --name containerapp >/dev/null 2>&1; then
  echo "Updating Azure Container Apps extension..."
  az extension update --name containerapp
else
  echo "Installing Azure Container Apps extension..."
  az extension add --name containerapp --upgrade
fi

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  echo "OPENAI_API_KEY is required. Export it before deploying the backend."
  exit 1
fi

if [[ "$AZURE_CONTAINER_REGISTRY" == "acrgenaimicroservice" ]]; then
  echo "Warning: AZURE_CONTAINER_REGISTRY is using the default name."
  echo "ACR names must be globally unique. Set AZURE_CONTAINER_REGISTRY before deploying."
fi

SUBSCRIPTION_NAME="$(az account show --query name -o tsv)"
SUBSCRIPTION_ID="$(az account show --query id -o tsv)"

echo "Prerequisite check passed."
echo "Azure subscription: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"
echo "Resource group: ${AZURE_RESOURCE_GROUP}"
echo "Location: ${AZURE_LOCATION}"
echo "ACR name: ${AZURE_CONTAINER_REGISTRY}"
echo "Backend app name: ${AZURE_BACKEND_APP_NAME}"
echo "Image name: ${AZURE_BACKEND_IMAGE_NAME}"
