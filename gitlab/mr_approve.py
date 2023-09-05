# systems
import os
# Gitlab api
import gitlab

# Gitlab Access
url = os.environ.get('CI_SERVER_URL')
token = os.environ.get('GITLAB_TOKEN')
gl = gitlab.Gitlab(url, private_token=token)
# Project info
project_id = os.environ.get('CI_PROJECT_ID')
merge_request_iid = os.environ.get('CI_MERGE_REQUEST_IID')

# Get MR info
merge_request = gl.projects.get(project_id).mergerequests.get(merge_request_iid)
mr_author = merge_request.author["username"]
# Get Approvals info
approvals = merge_request.approvals.get()
# Set array approved_by
approved_users = []
for obj in approvals.approved_by:
    approved_users.append(obj["user"]["username"])
# Targets
source_branch = merge_request.source_branch
target_branch = merge_request.target_branch


# Check approval
def approval():
    # Author MR
    print(f'MR Author: {mr_author}')

    # Revers change
    if source_branch in ("master", "main") and target_branch in ("dev", "develop"):
        print("Approved revers change")
        exit(0)

    # Check approval
    if approvals.approved:
        if mr_author in approved_users:
            print(f"{mr_author} is in the list of users who can skip own mr")
            exit(0)
        elif any(user for user in approved_users if user != mr_author):
            print("Approved by another user, skipping check")
            exit(0)
        elif mr_author in approved_users:
            print("You cannot approve your own merge request")
            exit(1)
        else:
            print("MR needs to be approved by a valid user")
            exit(1)
    else:
        print('MR needs to be approved')
        exit(1)


approval()
