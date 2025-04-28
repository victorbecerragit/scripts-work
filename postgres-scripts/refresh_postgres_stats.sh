#! /bin/bash

set -x
PSQL_HOST=${1:?"please provide PSQL host"}
PSQL_SOURCE_PREFIX=${2:?"please provide prefix"}
_u=${PG_USER?"PG_USER is not set"}
_p=${PG_PASSWORD?"PG_PASSWORD is not set"}

for dbname in $(psql -h "$PSQL_HOST" -d postgres -c "copy (select datname from pg_database where datname like '${PSQL_SOURCE_PREFIX}%') to stdout") ; do
    echo "==== ANALYZING $dbname ===="
    psql -h "$PSQL_HOST" -d $dbname -c "ANALYZE"
done
