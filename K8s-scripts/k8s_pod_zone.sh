#!/bin/bash

ns="${1?Namespace is required}"

RES=""
while IFS=" " read -r pod; do
  NODE=$(kubectl get pod "${pod}" -n "${ns}" -o json | jq -r '.spec.nodeName');
  ZONE=$(kubectl get node "${NODE}" -o json | jq -r '.metadata.labels."topology.kubernetes.io/zone"');
  RES="${RES}${pod}\t\t${ZONE}\n";
  echo -ne ".";
done <<<"$(kubectl get pods -n "${ns}" -o wide | grep Running | awk '{ print $1 }')"
echo ""

echo -e "${RES}" | column -t
