#!/bin/bash

# Authorization to AWS ECR
aws ecr get-login-password --region "${AWS_DEFAULT_REGION}" | helm registry login --username AWS --password-stdin "${ECR}"

# Set helmVersion
helm_version=$(helm -n "${NAMESPACE}" history "${HELM_CHART_NAME}" | grep '^[0-9]' | tail -n1 | awk '{{ print $8 }}' | cut -d'-' -f2)
print "Helm chat version:" "${helm_version}"

# Pull actual helm chart
helm pull oci://"${ECR}"/helm/"${HELM_ENV}"/"${HELM_REPO_NAME}" \
  --version "${helm_version}"

# Apply new image tag
helm -n "${NAMESPACE}" upgrade \
  --install "${HELM_CHART_NAME}" "${HELM_CHART_NAME}"-"${helm_version}".tgz \
  --reuse-values \
  --set images."${SERVICE_NAME}".tag="${IMAGE_TAG}" \
  --wait \
  --timeout 300s
