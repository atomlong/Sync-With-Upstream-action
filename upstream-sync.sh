#!/bin/sh

set -e
# do not quote GIT_PULL_ARGS or GIT_*_ARGS. As they may contain
# more than one argument.

# set user credentials in git config
config_git() {
    # store original user config for reset later
    ORIG_USER=$(git config --global --get --default="null" user.name)
    ORIG_EMAIL=$(git config --global --get --default="null" user.email)
    ORIG_PULL_CONFIG=$(git config --global --get --default="null" pull.rebase)

    if [ "${INPUT_GIT_USER}" != "null" ]; then
        git config --global user.name "${INPUT_GIT_USER}"
    fi

    if [ "${INPUT_GIT_EMAIL}" != "null" ]; then
        git config --global user.email "${INPUT_GIT_EMAIL}"
    fi

    if [ "${INPUT_GIT_PULL_REBASE_CONFIG}" != "null" ]; then
        git config --global pull.rebase "${INPUT_GIT_PULL_REBASE_CONFIG}"
    fi

    echo 'Git user and email credentials set for action' 1>&1
}

# reset user credentials to originals
reset_git() {
    if [ "${ORIG_USER}" = "null" ]; then
        git config --global --unset user.name
    else
        git config --global user.name "${ORIG_USER}"
    fi

    if [ "${ORIG_EMAIL}" = "null" ]; then
        git config --global --unset user.email
    else
        git config --global user.email "${ORIG_EMAIL}"
    fi

    if [ "${ORIG_PULL_CONFIG}" = "null" ]; then
        git config --global --unset pull.rebase
    else
        git config --global pull.rebase "${ORIG_PULL_CONFIG}"
    fi

    echo 'Git user name and email credentials reset to original state' 1>&1
    echo 'Git pull config reset to original state' 1>&1
}

### functions above ###
### --------------- ###
### script below    ###

# fail if upstream_repository is not set in workflow
if [ -z "${INPUT_UPSTREAM_REPOSITORY}" ]; then
    echo 'Workflow missing input value for "upstream_repository"' 1>&2
    echo '      example: "upstream_repository: https://github.com/atomlong/Sync-With-Upstream-action"' 1>&2
    exit 1
else
    UPSTREAM_REPO="${INPUT_UPSTREAM_REPOSITORY}"
fi

# set user credentials in git config
config_git

# ensure target_branch is checked out
if [ $(git branch --show-current) != "${INPUT_TARGET_BRANCH}" ]; then
    git checkout ${INPUT_GIT_CHECKOUT_ARGS} "${INPUT_TARGET_BRANCH}"
    echo 'Target branch ' ${INPUT_TARGET_BRANCH} ' checked out' 1>&1
fi

# set upstream to upstream_repository
git remote add upstream "${UPSTREAM_REPO}"

# check remotes in case of error
# git remote -v

# check latest commit hashes for a match, exit if nothing to sync
git fetch ${INPUT_GIT_FETCH_ARGS} upstream "${INPUT_UPSTREAM_BRANCH}"
NEW_COUNT=$(git rev-list upstream/${INPUT_UPSTREAM_BRANCH} ^${INPUT_TARGET_BRANCH} --count)
if [ "${NEW_COUNT}" = "0" ]; then
    echo "has_new_commits=false" >>${GITHUB_OUTPUT}
    echo 'No new commits to sync, exiting' 1>&1
    reset_git
    exit 0
fi

echo "has_new_commits=true" >>${GITHUB_OUTPUT}
# display commits since last sync
echo 'New commits being synced:' 1>&1
git log upstream/"${INPUT_UPSTREAM_BRANCH}" ^${INPUT_TARGET_BRANCH} ${INPUT_GIT_LOG_FORMAT_ARGS}

# sync from upstream to target_branch
echo 'Syncing...' 1>&1
# pull_args examples: "--ff-only", "--tags"
RET_MSG=$( { git pull --no-edit ${INPUT_GIT_PULL_ARGS} upstream "${INPUT_UPSTREAM_BRANCH}" 2>&1; echo "$?" >/tmp/RET_VAL.$$; } | tee >(cat - >&2) )
RET_VAL=$(cat /tmp/RET_VAL.$$)
rm -f /tmp/RET_VAL.$$
[ "${RET_VAL}" != 0 ] && {
echo 'Sync failed' 1>&1
git reset --hard origin/${INPUT_TARGET_BRANCH}
git checkout ${INPUT_GIT_CHECKOUT_ARGS} "${INPUT_TARGET_BRANCH}"
rm -fr ".git/rebase-merge"
RET_MSG=${RET_MSG//$'\r'/$'\n'}
RET_MSG="<p><font color=\"red\">Sync Failed</font></p><p>Error Message:</p><p><font style=\"background-color: gray;\">$(sed -r 's|^.*$|<br />&|' <<< ${RET_MSG})</font></p>"
RET_MSG="${RET_MSG//$'\n'/}"
echo "error_message=${RET_MSG}" >>${GITHUB_OUTPUT}
echo "has_new_commits=false" >>${GITHUB_OUTPUT}
} || {
echo 'Sync successful' 1>&1

# push to origin target_branch
echo 'Pushing to target branch...' 1>&1
while !(git push ${INPUT_GIT_PUSH_ARGS} origin "${INPUT_TARGET_BRANCH}"); do
git fetch ${INPUT_GIT_FETCH_ARGS} origin "${INPUT_TARGET_BRANCH}"
[ -z "$(git diff origin/${INPUT_TARGET_BRANCH} ^${INPUT_TARGET_BRANCH} --shortstat)" ] && break
git pull ${INPUT_GIT_PULL_ARGS} origin "${INPUT_TARGET_BRANCH}"
done
echo 'Push successful' 1>&1
}

# remove upstream remote
git remote remove upstream

# reset user credentials for future actions
reset_git
