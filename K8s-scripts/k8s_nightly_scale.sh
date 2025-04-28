#! /bin/bash
set -e

# region Functions
function getEnvironmentNamespaces() {
  kubectl get namespaces | grep -v NAME | grep -e ep- -e lq- -e epgcp | awk '{print $1}'
}
function getDeployments() {
  local namespace=$1
  kubectl get deployment -n "${namespace}" 2>/dev/null | grep -v NAME | grep -v 'No resources found' | awk '{print $1}'
}
function getStatefulSets() {
  local namespace=$1
  kubectl get statefulset -n "${namespace}" 2>/dev/null | grep -v NAME | grep -v 'No resources found' | awk '{print $1}'
}
function getReplicas() {
  local resourceKind=$1
  local namespace=$2
  local resourceName=$3
  kubectl get "${resourceKind}" "${resourceName}" -n "${namespace}" --ignore-not-found -o yaml | grep "replicas: " | tail -1 | awk '{print $2}'
}

function scaleReplicas() {
  local resourceKind=$1
  local namespace=$2
  local resourceName=$3
  local replicaCount=$4
  local storeReplicaState=$5

  local currentReplicas
  currentReplicas=$(getReplicas "${resourceKind}" "${namespace}" "${resourceName}")

  if [ "${currentReplicas}" == "" ]; then
    echoToWorkdirLog "Skipping scaleReplicas due to NotFound resource => ${resourceKind} ${namespace} ${resourceName}"
    return
  fi

  if [ "${storeReplicaState}" == "true" ]; then
    echo "${resourceKind} ${namespace} ${resourceName} ${currentReplicas}" >>"${REPLICA_STATE}"
  fi

  if [ "${DR}" == 1 ]; then
    echoToWorkdirLog "dry-run: state : ${resourceKind} ${namespace} ${resourceName} $(getReplicas "${resourceKind}" "${namespace}" "${resourceName}")"
    echoToWorkdirLog "dry-run: kubectl scale ${resourceKind} ${resourceName} -n ${namespace} --replicas=${replicaCount}"
  else
    echoToWorkdirLog "kubectl scale ${resourceKind} ${resourceName} -n ${namespace}  --replicas=${replicaCount}"
    kubectl scale "${resourceKind}" "${resourceName}" -n "${namespace}" --replicas="${replicaCount}" >>"${SCRIPT_LOGS}"
  fi
}
function scaleNamespaces() {
  local namespaces=$1
  for namespace in $namespaces; do
    for resourceName in $(getDeployments "${namespace}"); do
      scaleReplicas deployment "${namespace}" "${resourceName}" 0 true
    done
    for s in $(getStatefulSets "${namespace}"); do
      scaleReplicas sts "${namespace}" "${s}" 0 true
    done
  done
}

function shutdownApplicationPods() {
  echoToWorkdirLog "======== Shutting down application pods"
  scaleNamespaces "$(getEnvironmentNamespaces)"
}
function shutdownPlatformPods() {
  echoToWorkdirLog "======== Shutting down platform pods"
  scaleReplicas deployment monitoring "kafka-manager" 0 true
  scaleReplicas deployment monitoring "kafka-minion" 0 true
  scaleReplicas deployment monitoring "pgadmin-pgadmin4" 0 true
  scaleReplicas deployment monitoring "elasticsearch-exporter" 0 true
  scaleReplicas deployment logging "kibana" 0 true
  scaleReplicas deployment kube-system "traefik" 0 true
  scaleReplicas deployment apache-nifi "apache-nifi-ca" 0 true

  scaleReplicas statefulset kube-system "minio" 0 true

  entirePlatformNamespaces=$(printf "neo4j apache-nifi concourse")
  scaleNamespaces "${entirePlatformNamespaces}"
}
function shutdownPods() {
  # wipe previous replica state file
  echo -n >"${REPLICA_STATE}"
  shutdownApplicationPods
  shutdownPlatformPods
}

function uncordon() {
  if [ "${DR}" == 1 ]; then
    echoToWorkdirLog "dry-run: nodes to uncordon $(getCordonNodesSortedByDate | wc -l)"
  else
    local node=""
    local limit=0
    node=$(getCordonNode)
    while [ -n "${node}" ] && [ ${limit} -lt 20 ]; do
      echoToWorkdirLog "uncordon node (${limit}): ${node}"
      kubectl uncordon "${node}" >>"${SCRIPT_LOGS}"
      sleep 2
      node=$(getCordonNode)
      limit=$((limit + 1))
    done
  fi
}
function startup() {
  if [ -s "${REPLICA_STATE}" ]; then
    # https://github.com/koalaman/shellcheck/wiki/SC2155#problematic-code-in-the-case-of-local
    while read -r resourceKind namespace resourceName replicaCount; do
      scaleReplicas "${resourceKind}" "${namespace}" "${resourceName}" "${replicaCount}"
    done <"${REPLICA_STATE}"
  else
    echoToWorkdirLog "${REPLICA_STATE} previous replica state file is missing"
  fi
}

function countNodes() {
  kubectl get nodes | grep -cv NAME
}
function countAvailableNodes() {
  kubectl get nodes | grep -v NAME | grep -vc "SchedulingDisabled"
}
function countDisabledNodes() {
  kubectl get nodes | grep -v NAME | grep -c "SchedulingDisabled"
}
function countPods() {
  kubectl get pods -A | grep -vc NAME
}

function getOldestNode() {
  kubectl get nodes --sort-by='{.metadata.creationTimestamp}' | grep -v NAME | grep -v SchedulingDisabled | head -1 | awk '{print $1}'
}
function getCordonNodesSortedByDate() {
  kubectl get nodes --sort-by='{.metadata.creationTimestamp}' | grep -v NAME | grep SchedulingDisabled
}
function getCordonNode() {
  getCordonNodesSortedByDate | head -1 | awk '{print $1}'
}

function drainNode() {
  local nodeName=$1
  if [ "${DR}" == 1 ]; then
    echoToWorkdirLog "dry-run: kubectl drain ${nodeName} --delete-local-data --ignore-daemonsets"
  else
    echoToWorkdirLog "kubectl drain ${nodeName} --delete-local-data --ignore-daemonsets"
    kubectl drain "${nodeName}" --delete-local-data --ignore-daemonsets >>"${SCRIPT_LOGS}"
  fi
}
function drainUntilQuantity() {
  local desiredQuantity=$1
  local limit=0
  local sleep_sec=20
  while [ "$(countAvailableNodes)" -gt "${desiredQuantity}" ] && [ $limit -lt 20 ]; do
    echoToWorkdirLog ">> draining [try/limit: ${limit}/20 - nodes/target: $(countAvailableNodes)/$desiredQuantity]"
    drainNode "$(getOldestNode)"
    limit=$((limit + 1))
    if [ "${DR}" == 1 ]; then
      echoToWorkdirLog "dry-run: draining -> breaking loop"
      break
    fi
    sleep $sleep_sec #wait for the pods to be scheduled on new nodes
  done
  echoToWorkdirLog "drain completed [tries/limit: $limit/20 - nodes/target: $(countAvailableNodes)/$desiredQuantity]"
}
function drainAsMuchAsPossible() {
  drainUntilQuantity 6
  # TODO: found a solution to improve the drain quantity
}

function clusterState() {
  TIME_STAMP=$(date +%Y%m%resourceName-%H%M%S)
  echoToWorkdirLog "======= env($K8S_ENV) | action($K8S_ACTION) @ $TIME_STAMP ======"
  echoToWorkdirLog "Running nodes: $(countAvailableNodes)/$(countNodes)"
  echoToWorkdirLog "Running pods: $(countPods)"
}
function complete() {
  clusterState
  echoToWorkdirLog "======= End of run ======="
  # create replica state backup
  cp "${REPLICA_STATE}" "${REPLICA_STATE_BKP}"
  exit
}

function echoToWorkdirLog() {
  echo "${1}" >>"${SCRIPT_LOGS}"
}
# endregion

PATH=$PATH:/snap/bin

K8S_ENV=${1:?Provide environment (DEV/UAT/SIT/PRE)}
K8S_ACTION=${2:?Provide action (start,stop)}
DR=${3:-1}

DATE=$(date +%Y%m%d)
SCRIPT_WORKDIR="${HOME}/nightly_scheduler"
mkdir -p "${SCRIPT_WORKDIR}"
REPLICA_STATE="${SCRIPT_WORKDIR}/${K8S_ENV}.k8s-replica-state"
REPLICA_STATE_BKP="${SCRIPT_WORKDIR}/${K8S_ENV}.${DATE}.k8s-replica-state.backup"
SCRIPT_LOGS="${SCRIPT_WORKDIR}/${K8S_ENV}.${DATE}.${K8S_ACTION}.log"

K8S_ENV_LOWER=$(echo "${K8S_ENV}" | tr '[:upper:]' '[:lower:]')
# Deny run on PRD environment
if [ "${K8S_ENV_LOWER}" == "prd" ]; then
  echoToWorkdirLog "PRD detected. skipping run"
  exit 1
fi

# Check if DryRun value is properly set
if [ "${DR}" -ne "0" ] && [ "${DR}" -ne "1" ]; then
  echoToWorkdirLog "DryRun property is invalid"
  exit 1
elif [ "${DR}" == "1" ]; then
  REPLICA_STATE="${REPLICA_STATE}.dryrun"
  REPLICA_STATE_BKP="${REPLICA_STATE_BKP}.dryrun"
  SCRIPT_LOGS="${SCRIPT_LOGS}.dryrun"
  echoToWorkdirLog "====== DryRun enabled"
fi

SOURCE_FILE="${HOME}/Kubectlconfigscripts/epgcp${K8S_ENV_LOWER}.sh"
# Check if source is readable
if [ ! -r "${SOURCE_FILE}" ]; then
  echoToWorkdirLog "${SOURCE_FILE}"
  echoToWorkdirLog "Not able to read environment source file"
  exit 255
fi
# shellcheck disable=SC1090
source "${SOURCE_FILE}"

clusterState

if [ "${K8S_ACTION}" == "start" ]; then
  uncordon
  startup
elif [ "${K8S_ACTION}" == "stop" ]; then
  shutdownPods
  drainAsMuchAsPossible
else
  echoToWorkdirLog "======= Invalid Action. Skipping run ======"
fi

complete
