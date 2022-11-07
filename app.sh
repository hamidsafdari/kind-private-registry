cd app

IMAGE_TAG=$HOSTNAME:443/sample-app

echo '------------------------------'
echo 'building app image'
echo '------------------------------'
docker build -t $IMAGE_TAG .

echo ''
echo '------------------------------'
echo 'pushing app image to local registry'
echo '------------------------------'
docker push $IMAGE_TAG

echo ''
echo '------------------------------'
echo 'creating k8s deployment'
echo '------------------------------'
kubectl apply -f app.yaml

echo ''
echo '------------------------------'
echo 'waiting for deployment to become ready'
echo '------------------------------'
kubectl wait deployment sample-deployment --for condition=Available=True --timeout=90s

echo ''
echo '------------------------------'
echo 'deployment is ready now'
echo '------------------------------'
kubectl get all -o wide

echo ''
echo '------------------------------'
echo 'forwarding port 8080 to 80 in the pod'
echo 'you should be able to open 8080 in your browser now'
echo 'press Ctrl+C to exit'
echo '------------------------------'
kubectl port-forward deployments/sample-deployment 8080:80
