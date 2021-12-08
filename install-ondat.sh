curl -sSLo kubectl-storageos.tar.gz     https://github.com/storageos/kubectl-storageos/releases/download/v1.0.0/kubectl-storageos_1.0.0_linux_amd64.tar.gz     && tar -xf kubectl-storageos.tar.gz     && chmod +x kubectl-storageos     && sudo mv kubectl-storageos /usr/local/bin/     && rm kubectl-storageos.tar.gz
docker run -d --restart unless-stopped -v /usr/share/ca-certificates/:/etc/ssl/certs -p 2382:2382  --name etcd quay.io/coreos/etcd:latest  /usr/local/bin/etcd  -name etcd0  -auto-compaction-retention=3 -quota-backend-bytes=8589934592  -advertise-client-urls http://$(hostname -i):2382  -listen-client-urls http://0.0.0.0:2382
kubectl storageos install     --etcd-endpoints 192.168.101.90:2382     --admin-username "myuser"     --admin-password "my-password"

kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: "csi-provisioner-secret"
  namespace: "storageos"
  labels:
    app: "storageos"
type: "kubernetes.io/storageos"
data:
  username: bXl1c2Vy
  password: bXktcGFzc3dvcmQ=
---
apiVersion: v1
kind: Secret
metadata:
  name: "csi-node-publish-secret"
  namespace: "storageos"
  labels:
    app: "storageos"
type: "kubernetes.io/storageos"
data:
  username: bXl1c2Vy
  password: bXktcGFzc3dvcmQ=
---
apiVersion: v1
kind: Secret
metadata:
  name: "csi-controller-publish-secret"
  namespace: "storageos"
  labels:
    app: "storageos"
type: "kubernetes.io/storageos"
data:
  username: bXl1c2Vy
  password: bXktcGFzc3dvcmQ=
EOF
