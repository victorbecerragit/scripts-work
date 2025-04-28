#! /bin/bash

set -e

function GetPartitions() {
	local broker=$1
	local topic=$2
	kafka-topics --bootstrap-server $broker --describe --topic $topic | grep PartitionCount | awk '{print $4}'
}

function Rotation(){
        local broker=($(echo "$1" | tr ',' '\n'))
        local len=${#broker[@]}
        local idx=$(( $2 % $len ))
	local replica=$3

        broker=("${broker[@]:$idx:$len}" "${broker[@]:0:$idx}")
	echo "${broker[@]:0:$replica}" | sed 's/ /,/g'
}

function GenerateRepartitionFile() {
	local broker=$1
	local topic=$2
	local replica=$3
	local brokerids=$4
	local partitions=$(GetPartitions $broker $topic)
	local l=0
	echo '{"version":1,'
	echo ' "partitions":['
	while [[ $l -lt  $partitions ]]
	do
		if  [[ $l -eq $(( $partitions - 1 )) ]]; then
			echo  '  {"topic":"'$topic'","partition":'$l',"replicas":['$(Rotation $brokerids $l $replica)']}'
		else
			echo  '  {"topic":"'$topic'","partition":'$l',"replicas":['$(Rotation $brokerids $l $replica)']},'
		fi
		l=$(( $l +1 ))
	done
	echo ']}'
	
}

BROKER=${1:?borker lynqs-kafka-broker-dev-0001.gcp.fpprod.corp:9092}
ZOOKEEPER=${2:?zookeeper lynqs-kafka-zookeeper-dev-0001.gcp.fpprod.corp:2181}
TOPIC=${3:?topic name}
REPLICA=${4:?replication factor}
BROKERID_LIST=${5:?comma separeted broker id list: 0,1,2}
EXECUTE=${6:?execute: yes or no}

check=($(echo "$BROKERID_LIST" | tr ',' '\n'))
if [[ $REPLICA -gt ${#check[@]} ]];then
	echo "too many replicas ($REPLICA) for too few brokers (${#check[@]})"
	exit
fi

TS=$(date +%Y%m%d-%H%M%S)_$$

GenerateRepartitionFile $BROKER $TOPIC $REPLICA $BROKERID_LIST > /tmp/${TS}_reassign.json
cat /tmp/${TS}_reassign.json

if [[ $EXECUTE == "yes" ]]; then
	kafka-reassign-partitions --bootstrap-server $BROKER --zookeeper $ZOOKEEPER --reassignment-json-file /tmp/${TS}_reassign.json --execute
	sleep 10
	kafka-reassign-partitions --bootstrap-server $BROKER --zookeeper $ZOOKEEPER --reassignment-json-file /tmp/${TS}_reassign.json --verify
fi

rm -f /tmp/${TS}_reassign.json
