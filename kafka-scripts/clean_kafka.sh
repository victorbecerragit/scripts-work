#!/usr/bin/env bash

set -ex

zookeeper_host_port="${1?Zookeeper HOST with port is required}"
kafka_bootstrap_host_port="${2?Kafka Broker HOST with port is required}"
prefix="${3?Prefix is required}"

export PATH=$PATH:/opt/confluent/bin/

kafka-topics --zookeeper ${zookeeper_host_port} --delete --if-exists --topic ${prefix}.\*

kafka-topics --zookeeper ${zookeeper_host_port} --list | grep ${prefix} || :

group_ids=$(kafka-consumer-groups --bootstrap-server ${kafka_bootstrap_host_port} --list | grep ^${prefix} || :)
for group_id in ${group_ids}; do
kafka-consumer-groups --bootstrap-server ${kafka_bootstrap_host_port} --group ${group_id} --reset-offsets --to-earliest --all-topics --execute
done