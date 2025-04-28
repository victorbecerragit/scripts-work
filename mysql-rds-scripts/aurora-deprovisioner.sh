#!/bin/sh
​
TO_CREATE_INSTANCES=("d-eu-aurora-ecs-intesa-db4" "d-eu-aurora-ecs-intesa-db3")
REGION="eu-west-1"
​
remove_aurora_instance() {
​
    aws rds delete-db-instance \
        --db-instance-identifier $1 \
        --region "$REGION" \
        --query 'DBInstance.DBInstanceStatus' 
}
​
for i in "${TO_CREATE_INSTANCES[@]}"
do
    echo "removing $1"
    remove_aurora_instance  "$i" 
done
