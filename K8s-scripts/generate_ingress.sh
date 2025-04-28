ENVIRONMENT=${1:?"please provie namespace (epgcpdev,...,epgcpprd)"}
ACTION=${2}

helmfile -e $ENVIRONMENT -f ../helmfile.yaml template > template.$ENVIRONMENT.all

cat template.$ENVIRONMENT.all | ./bin/splitter -m "kind: Ingress" -e "api-$ENVIRONMENT" > ingress.$ENVIRONMENT.apps
cat template.$ENVIRONMENT.all | ./bin/splitter -m "kind: Ingress" | ./bin/splitter -m "api-$ENVIRONMENT" > ingress.$ENVIRONMENT.apis

function cleanAnnotation(){
	local ns=$1
	kubectl -n $ns get ingress | grep -v NAME | awk '{print $1}' | while read ing
	do
		kubectl -n $ns annotate ingress $ing kubectl.kubernetes.io/last-applied-configuration-
	done
}


if [ ${ACTION}"x" == "applyx" ]; then

    echo "applying change"
    kubectl -n $ENVIRONMENT apply -f ingress.$ENVIRONMENT.apps
    cleanAnnotation $ENVIRONMENT

    kubectl -n "api-$ENVIRONMENT" apply -f ingress.$ENVIRONMENT.apis
    cleanAnnotation "api-$ENVIRONMENT"

fi
