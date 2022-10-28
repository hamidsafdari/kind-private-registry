printf 'creating directories'
mkdir -p registry/{certs,auth,storage}
echo ' - OK'

echo ''
echo 'generating ssl certificate'
openssl req \
  -newkey rsa:4096 -nodes -sha256 -keyout registry/certs/domain.key \
  -addext "subjectAltName = DNS:$HOSTNAME,DNS:kind-registry" \
  -subj "/C=AF/ST=Kabul/L=Kabul/O=Home/OU=Room 3/CN=K8s Test Cert" \
  -x509 -days 365 -out registry/certs/domain.crt
echo '[OK]'

echo ''
echo 'generating credentials for registry'
docker run \
   --entrypoint htpasswd \
   httpd:alpine -Bbn testuser testpassword > registry/auth/htpasswd

echo '[OK]'

echo ''
echo 'importing keys into host'
echo 'you will be asked for the root password'
echo ''
sudo trust anchor --store registry/certs/domain.crt
sudo update-ca-trust
echo '[DONE]'

echo ''
echo 'creating the registry'
cd registry/
docker-compose -f docker-compose.yaml up -d
echo ''
echo '[DONE]'

echo ''
echo 'creating kind cluster'

is_registry_created=$(kind get clusters | grep kind-cluster)
if [ -n $is_registry_created ]; then
  kind delete cluster --name=kind-cluster
fi

cd ..
kind create cluster --config=kind-config.yaml

echo ''
echo 'importing key into kind cluster'
kind_container_id=$(docker ps | grep 'kindest/node' | awk '{printf $1'})
docker exec -it $kind_container_id update-ca-certificates

echo ''
echo 'connecting kind cluster network to the registry network'
docker network connect kind kind-registry >&/dev/null

echo 'creating k8s secret for private registry'
docker login -u testuser -p testpassword $HOSTNAME:443

cp $HOME/.docker/config.json ./docker-config.json
sed -i s/$HOSTNAME/kind-registry/ docker-config.json
 
kubectl create secret generic regcred \
  --from-file=.dockerconfigjson=docker-config.json \
  --type=kubernetes.io/dockerconfigjson

