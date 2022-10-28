# KinD with private HTTPS Registry

This guide will show you how to configure a KinD cluster
with a private registry that uses your self generated SSL
certificate. This will emulate your production environment
and you can avoid using options like docker's
*"insecureRegistries"*. There's also a project included so
you can test your setup.

### Steps:

1. Generate SSL certificate 
2. Create credentials for your registry
3. Import certificate into your host
4. Create private registry
5. Create KinD cluster
6. Import certificate into KinD cluster

> Note: Create a directory and run all the following 
> commands in the same directory.

### 1. Generate SSL certificate
You will need to generate a certificate that is valid for
both your own hostname (i.e., `cat /etc/hostname`) and for
your KinD cluster's hostname (i.e., kind-registry).

```shell
mkdir certs
openssl req \
  -newkey rsa:4096 -nodes -sha256 -keyout certs/domain.key \
  -addext "subjectAltName = DNS:arch.xps,DNS:kind-registry" \
  -subj "/C=AF/ST=Kabul/L=Kabul/O=Home/OU=Room 3/CN=K8s Test Cert" \
  -x509 -days 365 -out certs/domain.crt
```

If you want to use IPs to access your registry, add them to
the `subjectAltName` part like this:
```
subjectAltName = DNS:arch.xps,DNS:kind-registry,IP:127.0.0.1,IP:0.0.0.0
```

### 2. Create credentials for your registry
```shell
mkdir auth
docker run \
   --entrypoint htpasswd \
   httpd:alpine -Bbn testuser testpassword > auth/htpasswd
```

### 3. Import certificate into your host
The following commands may look different for your host's
operating system. I use Arch Linux but you should be able to
find the relevant commands for your OS pretty easily:
```shell
sudo trust anchor --store certs/domain.crt
sudo update-ca-trust
```

To check whether the previous steps were successful, run the
following and you should get `{}` as the output:
```lang=shell
curl -u testuser:testpassword https://arch.xps:443/v2/
```

### 4. Create Private Registry
Save the following to a file and run it with 
`docker-compose up -d`:
```yaml
# private-registry.yaml
version: '3.8'
services:
  registry:
    container_name: kind-registry
    restart: always
    image: registry:2
    ports:
      - 443:443
    environment:
      REGISTRY_HTTP_ADDR: 0.0.0.0:443
      REGISTRY_HTTP_TLS_CERTIFICATE: /certs/domain.crt
      REGISTRY_HTTP_TLS_KEY: /certs/domain.key
      REGISTRY_AUTH: htpasswd
      REGISTRY_AUTH_HTPASSWD_PATH: /auth/htpasswd
      REGISTRY_AUTH_HTPASSWD_REALM: Registry Realm
      REGISTRY_STORAGE_DELETE_ENABLED: true
    volumes:
      - ./storage:/var/lib/registry
      - ./certs:/certs
      - ./auth:/auth
```

### 5. Create KinD Cluster
```lang=yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: kind-cluster
nodes:
  - role: control-plane
    # This option mounts the host docker registry folder into
    # the control-plane node, allowing containerd to access them.
    extraMounts:
      - containerPath: '/usr/local/share/ca-certificates/extra/'
        hostPath: '/path/to/crt/directory'
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."arch.xps:443"]
    endpoint = ["https://kind-registry:443"]
```

You can run the above with:
```shell
kind create cluster --config=kind-config.yaml
```
Issuing `docker ps` should now show you two containers, one
for the private registry and the other for your kind
cluster.

```shell
$ docker ps
CONTAINER ID   IMAGE                  COMMAND                  CREATED        STATUS         PORTS                                             NAMES
1d1c4487a609   kindest/node:v1.25.2   "/usr/local/bin/entr…"   1 minute ago   Up 1 minute    127.0.0.1:42867->6443/tcp                         kind-cluster-control-plane
ebf758971282   registry:2             "/entrypoint.sh /etc…"   30 minutes ago Up 30 minutes  0.0.0.0:443->443/tcp, :::443->443/tcp, 5000/tcp   kind-registry
```

### 6. Import the certificate in your cluster
Find the container id for your KinD registry
(e.g., `docker ps`) and run:
```lang=sh
docker exec -it [container_id] update-ca-certificates
```
To make the registry accessible from inside your cluster, 
run this in your host:
```lang=sh
docker network connect kind kind-registry
```
Run the following in your host and your KinD cluster
container and the output should be `{}`:
```lang=shell
# in your host
curl -u testuser:testpassword https://arch.xps:443/v2/

# in your cluster container
docker exec -it [container_id] curl -u testuser:testpassword https://kind-registry:443/v2/
```
If running the above prints a warning about the SSL 
certificate, then one of the above commands did not work.

### Deploying to your cluster
To use your registry in Kubernetes, you have to save your 
registry's credentials in a `secret`.
1. On your host, login to your private registry with
   ```docker login [HOST_NAME:port]```. This should generate 
   a file in `~/.docker/config.json`.
2. Copy the file to a new location and change the hostname
   and port to `kind-registry:443`.
   ```
   {
    "auths": {
      "kind-registry:443": {
        "auth": "dGVzdHVzZXI6dGVzdHBhc3N3b3Jk"
      }
    }
   }
   ```
3. Create a secret in Kubernetes using the above file:
   ```
   kubectl create secret generic regcred \
      --from-file=.dockerconfigjson=<path/to/docker/config.json> \
      --type=kubernetes.io/dockerconfigjson
   ```
4. In your deployment config, add the following to the
   *"containers"* block:
   ```
   imagePullSecrets:
   - name: regcred
   ```
