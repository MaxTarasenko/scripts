#!/bin/bash

# Get the list of appeals for a given merge-request
approvals=$(curl -s --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/merge_requests/${CI_MERGE_REQUEST_IID}/approvals" | jq -r '.approved_by[].user.username')

# Check if there are users from the array USERS_TO_CHECK among the users who voted
for user in "${USERS_TO_CHECK[@]}"; do
  for approved_user in ${approvals}; do
    if [[ "${approved_user}" == "${user}" ]]; then
      echo "User ${approved_user} approved the merge request who can skip Sonar."
      check_user="true"
    fi
  done
done

# Get labels for the merge request
labels=$(curl -sH "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/merge_requests/${CI_MERGE_REQUEST_IID}" | jq -r '.labels')

# Check if the merge request has the SKIP_SONAR_CHECK label
if jq -e '.[] | select(. == "SKIP_SONAR_CHECK")' >/dev/null <<<"$labels"; then
  echo "The merge request has the SKIP_SONAR_CHECK label"
  check_label="true"
else
  echo "The merge request does not have the SKIP_SONAR_CHECK label"
fi

if [ -n "${check_user}" ] && [ -n "${check_label}" ]; then
  echo "Sonar skip check approved"
  export SONAR_ABORT_PIPE="false"
else
  echo "Checking for sonar skipping did not pass"
  export SONAR_ABORT_PIPE="true"
fi
