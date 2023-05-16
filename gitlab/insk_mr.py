# systems
import sys
import os
# Gitlab api
import gitlab

# Gitlab Access
url = os.environ.get('CI_API_V4_URL')
token = os.environ.get('GITLAB_TOKEN')
print(url, token)
gl = gitlab.Gitlab(url, private_token=token)
# Project info
project_id = os.environ.get('CI_PROJECT_ID')
merge_request_iid = os.environ.get('CI_MERGE_REQUEST_IID')
# An array of users to check
list_users_to_check = os.environ.get('USERS_TO_CHECK')

# Get MR info
merge_request = gl.projects.get(project_id).mergerequests.get(merge_request_iid)
mr_author = merge_request.author["username"]
# Get Approvals info
approvals = merge_request.approvals.get()
# Set array approved_by
approved_users = []
for obj in approvals.approved_by:
    approved_users.append(obj["user"]["username"])
# Set array labels
labels = merge_request.labels
# Targets
source_branch = merge_request.source_branch
target_branch = merge_request.target_branch


# Check approval
def approval():
    # Author MR
    print(f'MR Author: {mr_author}')
    # Check approval
    if approvals.approved:
        for user in approved_users:
            if user == mr_author:
                if user in list_users_to_check:
                    print(f"{user} is in the list of users who can skip own mr")
                    exit(0)
                else:
                    print("You cannot approve your own merge request")
                    exit(1)
            else:
                print("Approved")
    else:
        print('MR needs to be approved')


# Check Sonar skip
def sonar_skip():
    # Revers change skip sonar
    if source_branch in ("master", "main", "cicd-changes") and target_branch == "dev":
        print("export SONAR_ABORT_PIPE=false")
        return
    # Check users
    for user in approved_users:
        if user in list_users_to_check:
            if "SKIP_SONAR_CHECK" in labels:
                print("export SONAR_ABORT_PIPE=false")
                return
            else:
                print("export SONAR_ABORT_PIPE=true")
                return
        else:
            print("export SONAR_ABORT_PIPE=true")
            return


# Get the passed command line arguments
args = sys.argv[1:]

# Call the desired function based on the name passed
if len(args) > 0:
    if args[0] == 'approval':
        approval()
    elif args[0] == 'sonar_skip':
        sonar_skip()
    else:
        print("Invalid function")
else:
    print("You must specify a function to run")
    print("approval | sonar_skip")
