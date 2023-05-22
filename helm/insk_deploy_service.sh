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

# Check helm chart status
status_check_counter=0
max_status_retries=30
status_retry_wait=10

while true; do
  chart_status=$(helm -n "${NAMESPACE}" status "${HELM_CHART_NAME}" --output json | jq -r '.info.status')

  if [[ "$chart_status" == "deployed" ]]; then
    echo "Chart status is DEPLOYED, ready to upgrade"
    break
  elif [ $status_check_counter -ge $max_status_retries ]; then
    echo "Max status checks reached, exiting"
    echo "Check the helm chart in the cluster, what happened there"
    exit 1
  else
    status_check_counter=$((status_check_counter + 1))
    echo "Chart status is $chart_status, waiting until it becomes DEPLOYED"
    echo "Retrying after $status_retry_wait seconds ($status_check_counter/$max_status_retries)"
    sleep $status_retry_wait
  fi
done

# Apply new image tag
helm -n "${NAMESPACE}" upgrade \
  --install "${HELM_CHART_NAME}" "${HELM_CHART_NAME}"-"${helm_version}".tgz \
  --reuse-values \
  --set images."${SERVICE_NAME}".tag="${IMAGE_TAG}" \
  --wait \
  --timeout 300s

chart_status=$(helm -n "${NAMESPACE}" status "${HELM_CHART_NAME}" --output json | jq -r '.info.status')

if [[ "$chart_status" == "failed" ]]; then
  echo "Chart status is FAILED, initiating rollback"

  # Get the logs of the fallen container
  k8sPodName=$(kubectl -n "${NAMESPACE}" get pods \
    -o jsonpath="{range .items[*]}{.metadata.name}{' '}{.status.phase}{' '}{.spec.containers[*].image}{'\n'}{end}" | \
    grep "${ECR}/${IMAGE_PREFIX}/${IMAGE_NAME}:${IMAGE_TAG}" | \
    column -t -s " " | \
    awk '{print $1}')
  # Write logs to file
  kubectl -n "${NAMESPACE}" logs --since=15m "${k8sPodName}" > container.log
  # Write describe pod to file
  kubectl -n "${NAMESPACE}" describe pods "${k8sPodName}" > describe_container.log

  # Initiating rollback
  helm rollback -n "${NAMESPACE}" "${HELM_CHART_NAME}" --wait --timeout 120s
  if [ $? -ne 0 ]; then
    echo "Error during helm rollback"
    exit 1
  else
    echo "Upgrade failed. Helm successfully rolled back"
  fi
fi
