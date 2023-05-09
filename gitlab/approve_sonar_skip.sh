#!/bin/bash

# Получаем список аппрувов для заданного мерж-реквеста
approvals=$(curl --silent --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/merge_requests/${CI_MERGE_REQUEST_IID}/approvals" | jq -r '.approved_by[].user.username')

# Проверяем, есть ли пользователи из массива USERS_TO_CHECK среди проголосовавших пользователей
approved_users=()
for user in "${USERS_TO_CHECK[@]}"; do
  for approved_user in ${approvals}; do
    if [[ "${approved_user}" == "${user}" ]]; then
      approved_users+=("${user}")
      break
    fi
  done
done

# Если все пользователи из массива USERS_TO_CHECK проголосовали, то можно выполнить действие
if (( ${#approved_users[@]} == ${#USERS_TO_CHECK[@]} )); then
  echo 'All users approved the merge request.'
else
  echo -n 'Not all users approved the merge request. Approved users: '
  for user in "${approved_users[@]}"; do
    echo -n "${user} "
  done
  echo ""
fi
