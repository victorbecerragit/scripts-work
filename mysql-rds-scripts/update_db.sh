function handler () {
    EVENT_DATA=$1
    PLATFORM=$(echo $EVENT_DATA | ./bin/jq -r .platform)

    if [[ $PLATFORM == null ]]; then
      echo "Missing platform parameter"
      return 1
    fi

    curl -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" https://${GITLAB_HOST}/api/v4/projects/${GITLAB_PROJECT}/repository/files/$(echo $GITLAB_PATH | sed -e 's+/+%2F+g' -e 's+\.+%2E+g')\?ref\=$GITLAB_REF \
      | ./bin/jq -r .content | base64 -d > /tmp/automation.sql.gz

    DB_USER=$(./bin/redis-cli -h $REDIS_HOST -n 10 hget $PLATFORM db_user)
    DB_PASS=$(./bin/redis-cli -h $REDIS_HOST -n 10 hget $PLATFORM db_pass)
    DB_HOST=$(./bin/redis-cli -h $REDIS_HOST -n 10 hget $PLATFORM db_host)
    DB_NAME=$(./bin/redis-cli -h $REDIS_HOST -n 10 hget $PLATFORM db_name)

    ./bin/gzip -cd /tmp/automation.sql.gz | sed -e "s/automation_bafb2/$DB_USER/g" | ./bin/mysql -h$DB_HOST -u$DB_USER -p$DB_PASS $DB_NAME
    ./bin/mysql -h$DB_HOST -u$DB_USER -p$DB_PASS $DB_NAME -e "UPDATE core_setting SET param_value = 'http://$PLATFORM' WHERE param_name = 'url';"
    ./bin/mysql -h$DB_HOST -u$DB_USER -p$DB_PASS $DB_NAME -e "UPDATE core_setting SET param_value = '' WHERE param_name = 'custom_domain_original';"
    
    #Clear hydra cache
    for i in $(./bin/redis-cli -h $REDIS_HOST -n 9 keys ${PLATFORM}'*'); do ./bin/redis-cli -h $REDIS_HOST -n 9 del $i 2>&1 > /dev/null; done

    echo '{"response": "Database successfully imported"}'
}
