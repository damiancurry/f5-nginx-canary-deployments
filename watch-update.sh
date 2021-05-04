#!/bin/bash
#usage: bash watch-update.sh $run_number <app-name> <hostname> <path>
#usage: bash watch-update.sh $run_number demo-app demo.example.com '/'
set -x 

runnumber=$1
appname=$2
servername=$3
#uripath=$4
namespace='f5-nginx-canary-deployments'
oldsvc=`kubectl describe virtualserver $appname -n $namespace | grep Service | awk '{ print $2}'` 
newsvc="${appname}-svc-${runnumber}"
#replacenames='${oldsvc} ${newsvc} '
oldweight=50
newweight=50

#deploy virtualserver with header match
echo "Deploying ${newsvc} with beta header"
echo $oldsvc $newsvc
sed "s|existing-svc|${oldsvc}|g" kic/header-split.yaml | sed "s|new-svc|${newsvc}|g" > header-split.yaml
cat header-split.yaml
kubectl apply -f header-split.yaml


#check app is running fine with custom headers
ichostname=`kubectl get svc -A | grep ingress | awk '{print $5}'`
echo $ichostname
IC_IP=`getent ahostsv4 $ichostname | grep STREAM | head -n 1 | cut -d ' ' -f 1`

sleep 120
echo $IC_IP
headerreturncode=`curl -i -s -o /dev/null -w "%{http_code}" -H "release: beta" --resolve demo.example.com:80:$IC_IP http://demo.example.com/`
echo $headerreturncode
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
sed "s|existing-svc|${oldsvc}|g" kic/weight-split.yaml | sed "s|new-svc|${newsvc}|g" | sed "s|new-weight|${newweight}|g" | sed "s|old-weight|${oldweight}|g" > weight-split.yaml
cat weight-split.yaml
kubectl apply -f weight-split.yaml --namespace $namespace

#create port forwarding tunnel
ingresspod=`kubectl get pods -A | grep ingress | awk '{print $2}'`
kubectl port-forward $ingresspod 8080:8080 --namespace=default &
portforwardpid=$!
sleep 30
#generate some traffic
c=1
while [[ $c -le 50 ]]
do 
   curl -i -s -o /dev/null --resolve demo.example.com:80:$IC_IP http://demo.example.com/
   let c=c+1
done
#check the status code returns 
checkurl="http://localhost:8080/api/6/http/upstreams/vs_${namespace}_${appname}_${newsvc}"
echo ${checkurl}

#create a variable with the count of 400 errors
http4xxerrorcount=`curl -s $checkurl | jq '.' | grep 4xx | awk {'print $2'} | sed 's|,||g'`
http5xxerrorcount=`curl -s $checkurl | jq '.' | grep 5xx | awk {'print $2'} | sed 's|,||g'`
echo $http4xxerrorcount $http5xxerrorcount
kill $portforwardpid

if [ "$http4xxerrorcount" == '0' ] && [ "$http5xxerrorcount" == '0' ]
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
