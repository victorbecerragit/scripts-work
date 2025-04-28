#!/usr/bin/env bash

set -e

# Returns the pods that are governed by a deployment.
# Args:
#   $1 The name of the deployment
#   $2 The namespace
get_pods_for_deployment() {
    local deployment="${1?Deployment is required}"
    local namespace="${2?Namespace is required}"
    local jq_filter='.spec.selector.matchLabels | to_entries | .[] | "\(.key)=\(.value)"'
    local selectors
    mapfile -t selectors < <(kubectl get deployment "$deployment" --namespace "$namespace" --output=json | jq -r "$jq_filter")
    local selector
    selector=$(join_by , "${selectors[@]}")
    kubectl get pods --selector "$selector" --namespace "$namespace" --output jsonpath='{.items[*].metadata.name}'
}


# Joins strings by a delimiters
# Args:
#   $1 The delimiter
#   $* Additional args to join by the delimiter
join_by() {
    local IFS="$1"
    shift
    echo "$*"
}


# Wait for deployment chart.
# Args:
#   $1 The namespace to wait for developments
wait_for_deployments() {
    local namespace="${1?Namespace is required}"
     local error=
     # For deployments --wait may not be sufficient because it looks at 'maxUnavailable' which is 0 by default.
    for deployment in $(kubectl get deployments --namespace "$namespace" --output jsonpath='{.items[*].metadata.name}'); do
        kubectl rollout status "deployment/$deployment" --namespace "$namespace"
         # 'kubectl rollout status' does not return a non-zero exit code when rollouts fail.
        # We, thus, need to double-check here.
         local jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
         for pod in $(get_pods_for_deployment "$deployment" "$namespace"); do
            ready=$(kubectl get pod "$pod" --namespace "$namespace" --output jsonpath="$jsonpath")
            if [[ "$ready" != "True" ]]; then
                echo "Pod '$pod' did not reach ready state!"
                error=true
            else
                echo "Pod '$pod' reached ready state!"
            fi
        done
    done
     if [[ -n "$error" ]]; then
        return 1
    fi
}

wait_for_deployments ${1}
exit $?
