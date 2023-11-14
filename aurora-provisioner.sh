#!/bin/sh
​
MAIN_CLUSTER="d-eu-aurora-ecs-intesa-cluster"
TO_CREATE_INSTANCES=("d-eu-aurora-ecs-intesa-db4" "d-eu-aurora-ecs-intesa-db5")
REGION="eu-west-1"
​
create_aurora_instance() {
​
    echo "Creating Reader Instance $2 for $1"
​
    aws rds create-db-instance \
        --db-instance-identifier "$2" \
        --db-cluster-identifier "$1" \
        --db-subnet-group-name "d-rds-net-vpc" \
        --performance-insights-retention-period 7 \
        --db-parameter-group-name "live-euw1-ecs-intesa-aur8-db" \
        --db-instance-class "db.r6g.16xlarge" \
        --engine "aurora-mysql" \
        --promotion-tier "1" \
        --engine-version "8.0.mysql_aurora.3.04.0" \
        --no-publicly-accessible \
        --enable-performance-insights \
        --region "$REGION" \
        --query 'DBInstance.DBInstanceStatus' 
}
check_creation_status(){
​
    while :
    do
        ALL_SUCCESS=true
​
        for i in "${TO_CREATE_INSTANCES[@]}"
        do
            RESULT=$(aws rds describe-db-instances --db-instance-identifier $i --region "$REGION" --query 'DBInstances[*].DBInstanceStatus'  --output text )
            echo "$i $RESULT"
​
            if [ "$RESULT" != "available" ]; then
                ALL_SUCCESS=false
                break;
            fi
        done
​
        if [ $ALL_SUCCESS = true ]; then
            echo "done"
            break
        else 
            echo "still waiting"
            sleep 30
        fi
    done
}
​
​
for i in "${TO_CREATE_INSTANCES[@]}"
do
    create_aurora_instance "$MAIN_CLUSTER" "$i" 
done
​
check_creation_status
