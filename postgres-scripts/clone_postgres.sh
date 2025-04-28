#!/usr/bin/env bash

set -ex

set_credentials(){
  user="PGUSER_$1"
  password="PGPASSWORD_$1"
  export PGUSER="${!user}"
  export PGPASSWORD="${!password}"
}

set_credentials_svc(){
  export PGUSER="$1"
  if [[ $1 =~ "keycloak" ]]; then
    export PGPASSWORD="keycloak"
  else
    export PGPASSWORD="$1"
  fi
}

echo "debug: entering"
PSQL_SOURCE_HOST="${1?PostgresSQL Source Host is required}"
PSQL_TARGET_HOST="${2?PostgresSQL Target Host is required}"
PSQL_SOURCE_PREFIX="${3?Source Prefix is required}"
PSQL_TARGET_PREFIX="${4?Target Prefix is required}"
DATABASE_LIST="${5?DBCopyList is required}"

echo "debug: checking parameters"
if [[ -z $PGUSER_SOURCE ]]; then
 echo "Missing PGUSER_SOURCE env variable"
 exit 1
fi

if [[ -z $PGPASSWORD_SOURCE ]]; then
 echo "Missing PGPASSWORD_SOURCE env variable"
 exit 1
fi

if [[ -z $PGUSER_TARGET ]]; then
 echo "Missing PGUSER_TARGET env variable"
 exit 1
fi

if [[ -z $PGPASSWORD_TARGET ]]; then
 echo "Missing PGPASSWORD_TARGET env variable"
 exit 1
fi

DB_WHITE_LIST=()
echo "debug: splitting list"

echo "debug: creating white list"

all="${DATABASE_LIST//./ }"
for db_name1 in ${all}
do
  a=$PSQL_SOURCE_PREFIX"_"$db_name1
  echo $a
  DB_WHITE_LIST+=($a)
done

DBLIST=()

set_credentials "SOURCE"
for dbname in $(psql -h "$PSQL_SOURCE_HOST" -d postgres -c "copy (select datname from pg_database where datname like '${PSQL_SOURCE_PREFIX}%') to stdout") ; do
    echo "$dbname"
    DBLIST+=("$dbname")
done

echo "Copying dbcopylist"
for var in "${DBLIST[@]}"
do
  for db in "${DB_WHITE_LIST[@]}"
  do
    if [ $var == $db ]; then
        correctdb=${db//$PSQL_SOURCE_PREFIX/}
        finaldb=${PSQL_TARGET_PREFIX}${correctdb}
        echo "Copying ${var} to new environment ${finaldb}."
        set_credentials "SOURCE"
        source_user=$(psql -h "$PSQL_SOURCE_HOST" -d "${var}" -c "copy (select tableowner from pg_tables where schemaname = 'public') to stdout")

        set_credentials_svc $source_user

	if [[ ${db} =~ "amcgateway" ]];then
          pg_dump -v -Fp "${var}" -h "$PSQL_SOURCE_HOST" -f dumpfile.sql
          sed -i '/pg_trgm/d' dumpfile.sql
	else
          pg_dump -v -Fc "${var}" -h "$PSQL_SOURCE_HOST" -f dumpfile.sql
        #> dumpfile.sql
        fi

        set -e
        EXIT_CODE=0
        set_credentials "TARGET"
        createdb -h "$PSQL_TARGET_HOST" -U ${PGUSER} "$finaldb" | EXIT_CODE=$?
        echo $EXIT_CODE
        if [ "$EXIT_CODE" -eq "0" ];then
            psql -h "$PSQL_TARGET_HOST" -d postgres -c "GRANT pg_signal_backend TO ${PGUSER}"
            psql -h "$PSQL_TARGET_HOST" -d postgres << EOF
            SELECT pg_terminate_backend(pg_stat_activity.pid)
            FROM pg_stat_activity
            WHERE pg_stat_activity.datname = '${finaldb}'
            AND pid <> pg_backend_pid();
EOF
            dropdb -h "$PSQL_TARGET_HOST" "$finaldb"
            createdb -h "$PSQL_TARGET_HOST" -U ${PGUSER} "$finaldb"
        fi

        set_credentials_svc $source_user
        if [[ $db =~ "keycloak" ]]; then
            role=$(echo $finaldb | tr '[:upper:]' '[:lower:]')
            pg_restore -h "$PSQL_TARGET_HOST" -d $finaldb "dumpfile.sql"
            psql -h "$PSQL_TARGET_HOST" -d $finaldb -c "GRANT SELECT ON ALL TABLES IN SCHEMA public TO ${role};"
        else
	    if [[ ${db} =~ "amcgateway" ]]; then
		psql -h "$PSQL_TARGET_HOST" -d "$finaldb" < "dumpfile.sql"
	    else
            	pg_restore -h "$PSQL_TARGET_HOST" -d $finaldb "dumpfile.sql"
	    fi
        fi
        rm dumpfile.sql
    fi
  done
done
