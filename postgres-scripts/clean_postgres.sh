#!/usr/bin/env bash

set -ex

postgresql_host="${1?PostgresSQL Host is required}"
prefix="${2?Prefix is required}"

if [[ -z $PGUSER ]]; then
 echo "Missing PGUSER env variable"
 exit 1
fi

if [[ -z $PGPASSWORD ]]; then
 echo "Missing PGPASSWORD env variable"
 exit 1
fi

for dbname in $(psql -h "$postgresql_host" -d postgres -c "copy (select datname from pg_database where datname like '${prefix}%') to stdout") ; do
    echo "$dbname"
    psql -h "$postgresql_host" -d postgres << EOF
    SELECT pg_terminate_backend(pg_stat_activity.pid)
    FROM pg_stat_activity
    WHERE pg_stat_activity.datname = '${dbname}'
    AND pid <> pg_backend_pid();
EOF
    dropdb --maintenance-db=postgres -h "$postgresql_host" -e --if-exists "$dbname"
done
