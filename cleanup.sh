PROJECT_DIR=$(pwd)

docker-compose -f $PROJECT_DIR/registry/docker-compose.yaml rm -sfv  >&/dev/null 
docker network rm registry_default >&/dev/null

kind delete -q cluster --name=kind-cluster
docker network rm kind >&/dev/null 

cert_file=registry/certs/domain.crt
if [ -f $cert_file ]; then
  sudo trust anchor --remove registry/certs/domain.crt
  sudo update-ca-trust
fi

sudo rm -rf $PROJECT_DIR/registry/{auth,certs,storage}

