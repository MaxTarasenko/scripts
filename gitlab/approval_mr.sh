#!/bin/bash

MR_AUTHOR=$(curl -sH "PRIVATE-TOKEN: $GITLAB_TOKEN" "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/merge_requests/${CI_MERGE_REQUEST_IID}" | jq -r ".author.username")

echo "MR_AUTHOR: ${MR_AUTHOR}"

# Get approve
approve=$(curl -sH "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/merge_requests/${CI_MERGE_REQUEST_IID}/approvals" | jq -r '.approved')

# Get the list of appeals for a given merge-request
approvals=$(curl -sH "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/merge_requests/${CI_MERGE_REQUEST_IID}/approvals" | jq -r '.approved_by[].user.username')

if [ "${approve}" == "true" ]; then
  for approveal_user in "${approvals[@]}"; do
    if [ "${approveal_user}" == "${MR_AUTHOR}" ]; then
      for user in "${USERS_TO_CHECK[@]}"; do
        if [ "${user}" == "${approveal_user}" ]; then
          echo "${user} is in the list of users who can skip sonar"
          exit 0
        else
          echo "You cannot approve your own merge request"
          exit 1
        fi
      done
    fi
  done
else
  echo "MR needs to be approved"
  exit 1
fi
