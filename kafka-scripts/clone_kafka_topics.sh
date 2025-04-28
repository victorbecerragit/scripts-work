#!/usr/bin/env bash

set -e

kafka_bootstrap_source="${1?Kafka Broker SOURCE:PORT is required}"
kafka_bootstrap_target="${2?Kafka Broker TARGET:PORT is required}"
env_source_prefix=${3?Uppercase Source Environment prefix is required}
env_target_prefix=${4?Uppercase Target Environment prefix is required}
topics_list="${5?List of topics separated by comma is required}"

for TOPIC in $(echo "$topics_list" | sed "s/,/ /g")
do
    echo "Cloning '${TOPIC}'"
    TOPIC_DESCRIBE=$(kafka-topics --bootstrap-server "${kafka_bootstrap_source}" --describe --topic "${env_source_prefix}_${TOPIC}" | grep -m1 "")
    echo "Describe: '${TOPIC_DESCRIBE}'"

    # Replication Factor
    RF=$(echo "${TOPIC_DESCRIBE}" | grep -o -P '.{0}ReplicationFactor: \K.{1}')
    # Partitions Count
    PC=$(echo "${TOPIC_DESCRIBE}" | grep -o -P '.{0}PartitionCount: \K.{1}')
    # Configs
    RAW_CONF=$(echo "${TOPIC_DESCRIBE}" | grep -o -P '.{0}Configs: \K.*')
    CONF=$(echo $RAW_CONF | sed 's/,/ --config /g' | tr -d '"')

    kafka-topics --bootstrap-server "${kafka_bootstrap_target}" \
      --create \
      --topic "${env_target_prefix}_${TOPIC}" \
      --replication-factor "${RF}" \
      --partitions "${PC}" \
      --config $CONF
done
