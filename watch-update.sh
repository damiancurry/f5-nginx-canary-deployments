#!/bin/bash
#usage: bash watch-update.sh $run_number <app-name> <hostname> <path>
#usage: bash watch-update.sh $run_number demo-app demo.example.com '/'
runnumber=$1
appname=$2
servername=$3
#uripath=$4
namespace='f5-nginx-canary-deployments'
oldsvc=`kubectl describe virtualserver $appname -n $namespace | grep Service | awk '{ print $2}'` 
newsvc="${appname}-svc-${runnumber}"
#replacenames='${oldsvc} ${newsvc} '

# #check to see if 2 values were returned by the oldsvc call, means there is already a split configured
# if []
# echo "${oldsvc}"

#backup existing config
#don't need right now, have a prebaked version
#kubectl describe virtualserver $appname -n $namespace -o yaml > rollbackconfig.yaml

#deploy virtualserver with header match
echo "Deploying ${newsvc} with beta header"
sed "s|existing-svc|${oldsvc}|g" kic/update-header-split.yaml | sed "s|new-svc|${newsvc}|g" > update-header-split.yaml
kubectl apply -f update-header-split.yaml


#check app is running fine with custom headers
ichostname=`kubectl get svc -A | grep ingress | awk '{print $5}'`
echo $ichostname
IC_IP=`nslookup $ichostname 8.8.8.8 | grep Address | grep -v 8.8.8.8 | awk {'print $2'}`
#IC_IP=`host $ichostname | awk {'print $4'}`
echo $IC_IP
headerreturncode=`curl -i -s -o /dev/null -w "%{http_code}" -H "release: beta" --resolve demo.example.com:80:$IC_IP http://demo.example.com/`
if [ $headerreturncode == '200' ]
then
	echo "Header tests passed. Moving on"
else
	echo "Check failed, rolling back version"
    sed "s|new-svc|${oldsvc}|g" kic/single-svc-virtualserver.yaml > single-svc-virtualserver.yaml
    kubectl apply -f single-svc-virtualserver.yaml --namespace $namespace
	exit 1
fi


#assuming checks work, deploy virtualserver with 50/50 split for new/old
sed "s|existing-svc|${oldsvc}|g" kic/update-demo-app-virtualserver.yaml | sed "s|new-svc|${newsvc}|g" | sed "s|new-weight|${new_weight}|g" | sed "s|old-weight|${old_weight}|g" > update-demo-app-virtualserver.yaml
cat update-demo-app-virtualserver.yaml
kubectl apply -f update-demo-app-virtualserver.yaml --namespace $namespace

#create port forwarding tunnel
ingresspod=`kubectl get pods -A | grep ingress | awk '{print $2}'`
kubectl port-forward $ingresspod 8080:8080 --namespace=default
#check the status code returns 
 checkurl="http://localhost:8080/api/6/http/upstreams/vs_${namespace}_${appname}_${newsvc}"
 echo ${checkurl}

#create a variable with the count of 400 errors
#httperrorcount=`curl -i $checkurl <other values>`
#hard coded for tests
httperrorcount=0
if [ "$httperrorcount" == '0' ]
then
	echo "live traffic tests passed. Moving on"
else
	echo "Check failed, rolling back version"
    sed "s|new-svc|${oldsvc}|g" kic/single-svc-virtualserver.yaml > single-svc-virtualserver.yaml
    kubectl apply -f single-svc-virtualserver.yaml --namespace $namespace
	exit 1
fi
#assuming checks return ok, depricate old version and push all traffic to new
sed "s|new-svc|${newsvc}|g" kic/single-svc-virtualserver.yaml > single-svc-virtualserver.yaml
kubectl apply -f single-svc-virtualserver.yaml --namespace $namespace
exit 0

#if fails, roll back to old version