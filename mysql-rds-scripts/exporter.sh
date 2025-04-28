#!/bin/bash
#
# Previously install go 1.16.2 in the service machine.
# https://www.itzgeek.com/how-tos/linux/centos-how-tos/install-go-1-7-ubuntu-16-04-14-04-centos-7-fedora-24.html
# Set environment variables required by exporter.

EXPORTER_PATH="./"
PLATFORM_FILE="all-platforms.txt"
LOGS_PATH="./logs"

#Env Variables per environment.
export AWS_ACCESS_KEY_ID="xxxxx" #audit-migration-user credentials
export AWS_SECRET_ACCESS_KEY="xxxxx" #audit-migration-user credentials
export AWS_REGION=eu-central-1
export REDIS_HOST=d-eu-c-redis-rg-ro.mkwdmt.ng.0001.euc1.cache.amazonaws.com
export LOCAL_REDIS_HOST=localhost
export AWS_EXPORT_BUCKET=euc1-ecs-audittrail-v2-lihnl7
mkdir $LOGS_PATH

# Start local redis instance
sudo docker run -d --name redis-auditrail -p 6379:6379 redis:latest

cd "$EXPORTER_PATH"

#Get all platform from Redis
redis-cli -h $REDIS_HOST -n 10 keys '*' | awk -F'"' '{print $1}' > all-platforms.txt

cust_func(){
  sh -c "sleep 0.2 && ./audit_exporter $line > $LOGS_PATH/job_$line.log 2>&1"
}

count = 0
while read line;
do
  cust_func "$line" &
  ((count ++))
  if [ $count -eq 60 ]
     then
         ((count=0))
	 wait
  fi
done < "$PLATFORM_FILE"
