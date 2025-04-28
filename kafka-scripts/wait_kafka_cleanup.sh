#!/usr/bin/env bash

set -ex

zookeeper_host_port="${1?Zookeeper HOST with port is required}"
prefix="${2?Prefix is required}"
timeout="${3?Waiting timeout is required}"

export PATH=$PATH:/opt/confluent/bin/

kafka-topics --zookeeper ${zookeeper_host_port} --list | grep ${prefix} || :


wait_topics_deleted() {
  local zk="$1";
  local prefix="$2";
  local wait_seconds="${3:-10}"; # 10 seconds as default timeout

  until test $((wait_seconds--)) -eq 0 -o "$(kafka-topics --zookeeper ${zk} --list | grep ${prefix} || :)" = ""; do sleep 5; done

  ((++wait_seconds))
}

wait_topics_deleted "${zookeeper_host_port}" "${prefix}" ${timeout} || {
  echo "Kafka log files not deleted after waiting for $? seconds: '$prefix'"
  exit 1
}
