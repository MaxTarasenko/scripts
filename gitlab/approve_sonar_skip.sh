#!/bin/bash

# Получаем список аппрувов для заданного мерж-реквеста
approvals=$(curl -s --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/merge_requests/${CI_MERGE_REQUEST_IID}/approvals" | jq -r '.approved_by[].user.username')

# Проверяем, есть ли пользователи из массива USERS_TO_CHECK среди проголосовавших пользователей
for user in "${USERS_TO_CHECK[@]}"; do
  for approved_user in ${approvals}; do
    if [[ "${approved_user}" == "${user}" ]]; then
      echo "User ${approved_user} approved the merge request who can skip Sonar."
      export SONAR_ABORT_PIPE="false"
      break
    fi
  done
done
