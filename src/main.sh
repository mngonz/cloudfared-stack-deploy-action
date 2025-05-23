#!/usr/bin/env bash

set -e

echo "Running: ${0} as: $(whoami) in: $(pwd)"

function cleanup_trap() {
    _ST="$?"
    if [[ "${_ST}" != "0" ]]; then
        echo -e "\u001b[31;1mScript Exited with Error: ${_ST}"
    fi
    if [ -z "${INPUT_SSH_KEY}" ];then
        echo -e "\u001b[35mCleaning Up authorized_keys on: ${INPUT_HOST}"
        ssh -p "${INPUT_PORT}" "${INPUT_USER}@${INPUT_HOST}" \
            "sed -i '/docker-stack-deploy-action/d' ~/.ssh/authorized_keys"
    fi
    if [[ "${_ST}" == "0" ]]; then
        echo -e "\u001b[32;1mFinished Success."
    fi
    exit "${_ST}"
}

mkdir -p /root/.ssh
chmod 0700 /root/.ssh

if [ -z "${INPUT_SSH_KEY}" ];then
    echo -e "\u001b[36mCreating and Copying SSH Key to: ${INPUT_HOST}"
    ssh-keygen -q -f /root/.ssh/id_rsa -N "" -C "docker-stack-deploy-action"
    eval "$(ssh-agent -s)"
    ssh-add /root/.ssh/id_rsa

    sshpass -p "${INPUT_PASS}" \
        ssh-copy-id -p "${INPUT_PORT}" -i /root/.ssh/id_rsa \
            "${INPUT_USER}@${INPUT_HOST}"
else
    echo -e "\u001b[36mAdding SSH Key to SSH Agent"
    echo -e "${INPUT_SSH_KEY}" > /root/.ssh/id_rsa
    chmod 0600 /root/.ssh/id_rsa
    eval "$(ssh-agent -s)"
    ssh-add /root/.ssh/id_rsa
fi

# Create hosts file config
{
  echo "Host ${INPUT_HOST}"
  echo "User ${INPUT_USER}"
  echo "IdentityFile ~/.ssh/id_rsa"
  echo "UserKnownHostsFile ~/.ssh/known_hosts"
  echo "ServerAliveInterval 240"
} >> /root/.ssh/config
# I've decided to accept new because isn't any connection going to be new anyway?
echo "StrictHostKeyChecking accept-new" >> /root/.ssh/config
if [ -z "${INPUT_CF_TOKEN_ID}" ] && [ -z "${INPUT_CF_TOKEN_SECRET}" ]
then
    echo "ProxyCommand /usr/bin/cloudflared access ssh --hostname %h" >> /root/.ssh/config
else
    echo "ProxyCommand /usr/bin/cloudflared access ssh --hostname %h --id ${INPUT_CF_TOKEN_ID} --secret ${INPUT_CF_TOKEN_SECRET}" >> /root/.ssh/config
fi

trap cleanup_trap EXIT HUP INT QUIT PIPE TERM

echo -e "\u001b[36mVerifying Docker and Setting Context."
docker context create remote --docker "host=ssh://${INPUT_USER}@${INPUT_HOST}:${INPUT_PORT}"
docker context use remote
docker info > /dev/null

if [ -n "${INPUT_ENV_FILE}" ];then
    echo -e "\u001b[36mSourcing Environment File: ${INPUT_ENV_FILE}"
    stat "${INPUT_ENV_FILE}"
    set -a
    # shellcheck disable=SC1090
    source "${INPUT_ENV_FILE}"
fi

echo -e "\u001b[36mDeploying Stack: \u001b[37;1m${INPUT_NAME}"
if [ -n "${INPUT_PRIVATE_REGISTRY_URL}" ] && [ -n "${INPUT_PRIVATE_REGISTRY_USERNAME}" ] && [ -n "${INPUT_PRIVATE_REGISTRY_PASSWORD}" ];then
  echo -e "\u001b[36mDeploying with registry auth \u001b[37;1m"
  echo "${INPUT_PRIVATE_REGISTRY_PASSWORD}" | docker login -u "${INPUT_PRIVATE_REGISTRY_USERNAME}" --password-stdin "${INPUT_PRIVATE_REGISTRY_URL}" 2>/dev/null || { echo "Docker login failed!"; exit 1; }
  docker stack deploy --with-registry-auth --prune -c "${INPUT_FILE}" "${INPUT_NAME}"
else
  docker stack deploy --prune -c "${INPUT_FILE}" "${INPUT_NAME}"
fi
