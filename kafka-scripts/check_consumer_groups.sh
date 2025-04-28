## returns a list of topics with the correspodning active consumer groups

KAFKA_BOOTSTRAP_HOST_PORT=${1?please provide kafka broker host:port}

kafka-consumer-groups --bootstrap-server $KAFKA_BOOTSTRAP_HOST_PORT --describe --all-groups | awk '$8 != "-" {print $2,$1, $8}' | sed 's/\///' | sort -u -r
