private_key_file='registry/certs/domain.key'
public_key_file='registry/certs/domain.crt'

printf 'creating directories'
mkdir -p registry/{certs,auth,storage}
echo ' - OK'
echo ''

if [[ -f $private_key_file && -f $public_key_file ]]; then
  echo 'TLS certificate files exist'
  printf 'generate certificate again? (Y/n) '
  read gen_cert
fi

if [[ -z $gen_cert || $gen_cert == 'y' || $gen_cert == 'Y' ]]; then
  rm -f $private_key_file $public_key_file

  echo 'generating TLS certificate'
  openssl req \
    -newkey rsa:4096 -nodes -sha256 -keyout $private_key_file \
    -addext "subjectAltName = DNS:$HOSTNAME,DNS:kind-registry,IP:127.0.0.1,IP:::1,IP:0.0.0.0" \
    -subj "/C=AF/ST=Kabul/L=Kabul/O=Home/OU=Room 3/CN=K8s Test Cert" \
    -x509 -days 365 -out $public_key_file
  echo '[OK]'
fi

printf 'enter registry username: (default testuser) '
read reg_user
printf 'enter registry password: (default testpassword) '
read reg_password

if [ -z $reg_user ]; then
  reg_user='testuser'
fi

if [ -z $reg_password ]; then
  reg_password='testpassword'
fi

echo ''
echo 'Generating credentials for registry'
docker run --rm \
   --entrypoint htpasswd \
   httpd:alpine -Bbn $reg_user $reg_password > registry/auth/htpasswd

echo '[OK]'


printf 'Import certificate into host? Only works on Arch Linux for now. (Y/n) '
read import_keys

if [[ -z $import_keys || $import_keys == 'y' || $import_keys == 'Y' ]]; then
  echo ''
  echo 'Enter root password'
  echo ''
  sudo trust anchor --store registry/certs/domain.crt
  sudo update-ca-trust
  echo '[DONE]'
fi


registry_exists=$(docker ps -q -f name=kind-registry)

if [[ -n $registry_exists ]]; then 
  echo ''
  printf 'Private registry already exists. Create again? (Y/n) '
  read create_registry
fi

if [[ -z $create_registry || $create_registry == 'y' || $create_registry == 'Y' ]]; then
  echo ''
  echo 'Creating private registry'
  docker-compose -f registry/docker-compose.yaml up -d
  echo ''
  echo '[DONE]'
fi



cluster_exists=$(kind get clusters -q | grep kind-cluster)

if [[ -n $cluster_exists ]]; then
  echo ''
  printf 'KinD cluster already exists. Delete and create cluster again? (Y/n) '
  read create_cluster

  if [[ -z $create_cluster || $create_cluster == 'y' || $create_cluster == 'Y' ]]; then
    kind delete cluster --name=kind-cluster
  fi
fi

if [[ -z $create_cluster || $create_cluster == 'y' || $create_cluster == 'Y' ]]; then
  echo 'Creating KinD cluster'
  kind create cluster --config=kind-config.yaml
  
  echo ''
  echo 'Importing key into kind cluster'
  for id in $(docker ps -q --filter=name=^kind-cluster); do
   docker exec -it $id update-ca-certificates
  done
  
  echo ''
  echo 'Connecting kind cluster to registry network'
  docker network connect kind kind-registry >&/dev/null
fi

echo 'Creating k8s secret (regcred) for private registry'
docker login -u $reg_user -p $reg_password $HOSTNAME:443

cp $HOME/.docker/config.json ./docker-config.json
sed -i s/$HOSTNAME/kind-registry/ docker-config.json
 
kubectl create secret generic regcred \
  --from-file=.dockerconfigjson=docker-config.json \
  --type=kubernetes.io/dockerconfigjson

