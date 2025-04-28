#!/bin/bash

ns="${1?Namespace is required}"

RES=""
while IFS=" " read -r pod; do
  NODE=$(kubectl get pod "${pod}" -n "${ns}" -o json | jq -r '.spec.nodeName');
  CPU=$(kubectl top pod "${pod}" -n "${ns}" --no-headers 2>/dev/null |awk '{print $2}');
  ZONE=$(kubectl get node "${NODE}" -o json | jq -r '.metadata.labels."topology.kubernetes.io/zone"');
  RES="${RES}${pod}\t\t${CPU}\t\t${ZONE}\t\t${NODE}\n";
  echo -ne ".";
done <<<"$(kubectl get pods -n "${ns}" -o wide | grep Running | awk '{ print $1 }')"
echo ""
