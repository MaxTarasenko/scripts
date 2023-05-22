#!/bin/bash

# Authorization to AWS ECR
aws ecr get-login-password --region "${AWS_DEFAULT_REGION}" | helm registry login --username AWS --password-stdin "${ECR}"
if [ $? -ne 0 ]; then
    echo "Error during AWS ECR authorization"
    exit 1
fi

# Set helmVersion
helm_version=$(helm -n "${NAMESPACE}" history "${HELM_CHART_NAME}" | grep '^[0-9]' | tail -n1 | awk '{{ print $8 }}' | cut -d'-' -f2)
if [ $? -ne 0 ]; then
    echo "Error while setting helmVersion"
    exit 1
fi
echo "Helm chat version:" "${helm_version}"

# Pull actual helm chart
helm pull oci://"${ECR}"/helm/"${HELM_ENV}"/"${HELM_REPO_NAME}" --version "${helm_version}"
if [ $? -ne 0 ]; then
    echo "Error while pulling helm chart"
    exit 1
fi

# Apply new image tag
retry_counter=0
max_retries=5
retry_wait=30

while true; do
  helm -n "${NAMESPACE}" upgrade \
    --install "${HELM_CHART_NAME}" "${HELM_CHART_NAME}"-"${helm_version}".tgz \
    --reuse-values \
    --set images."${SERVICE_NAME}".tag="${IMAGE_TAG}" \
    --wait \
    --timeout 300s

  exit_status=$?

  if [ $exit_status -eq 0 ]; then
    break
  elif [ $retry_counter -ge $max_retries ]; then
    echo "Max retries reached, aborting"
    exit $exit_status
  else
    retry_counter=$((retry_counter+1))
    echo "Upgrade failed, retrying after $retry_wait seconds ($retry_counter/$max_retries)"
    sleep $retry_wait
  fi
done
