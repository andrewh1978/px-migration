NAMESPACE=postgres
LABEL=px/migrate=true

WORKDIR=/var/tmp/px-migration
rm -rf $WORKDIR
mkdir -p $WORKDIR/{pvc,pv-old,pv-new,logs}

function pxctl {
  ns=$(kubectl get pod -lname=portworx -A -o jsonpath='{.items[].metadata.namespace}')
  pod=$(kubectl get pod -lname=portworx -A -o jsonpath='{.items[].metadata.name}')
  kubectl exec -n $ns -c portworx $pod -- /opt/pwx/bin/pxctl --color $*
}


IFS='' read -r -d '' jobtemplate <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: migrate-job-script
  namespace: NAMESPACE
data:
  entrypoint.sh: |-
    #!/bin/sh
    apk add rsync
    rsync -av /migrate-old/ /migrate-new
    df -h
---
apiVersion: batch/v1
kind: Job
metadata:
  name: migrate-job
  namespace: NAMESPACE
spec:
  template:
    spec:
      terminationGracePeriodSeconds: 0
      restartPolicy: Never
      containers:
      - name: migrate-job
        securityContext:
          runAsUser: 0
        image: alpine:3.15.0
        command:
        - /entrypoint.sh
        volumeMounts:
        - name: migrate-job-script
          mountPath: /entrypoint.sh
          readOnly: true
          subPath: entrypoint.sh
        - name: migrate-old
          mountPath: /migrate-old
        - name: migrate-new
          mountPath: /migrate-new
      volumes:
      - name: migrate-old
        persistentVolumeClaim:
          claimName: PVC
      - name: migrate-new
        persistentVolumeClaim:
          claimName: px-migration-temp
      - name: migrate-job-script
        configMap:
          defaultMode: 0700
          name: migrate-job-script
EOF

# Create Portworx StorageClass
kubectl apply -f - <<EOF
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: portworx-sc
provisioner: kubernetes.io/portworx-volume
parameters:
  repl: "1"
allowVolumeExpansion: true
reclaimPolicy: Retain
EOF

# Get list of PVCs
PVCs=$(kubectl get pvc -l $LABEL -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}')

# Get list of PVs
PVs=$(kubectl get pvc -l $LABEL -n $NAMESPACE -o jsonpath='{.items[*].spec.volumeName}')

# Patch PVs so they are not deleted
for pv in $PVs; do
  kubectl patch pv $pv -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
done

for pvc in $PVCs; do
  # Get PVC size
  size=$(kubectl get pvc $pvc -n $NAMESPACE -o jsonpath='{.spec.resources.requests.storage}')
  # Create temp PVC
  kubectl apply -n $NAMESPACE -f - <<EOF
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
   name: px-migration-temp
   annotations:
     volume.beta.kubernetes.io/storage-class: portworx-sc
spec:
   accessModes:
     - ReadWriteOnce
   resources:
     requests:
       storage: $size
EOF
  kubectl patch pvc px-migration-temp -n $NAMESPACE -p '{"spec":{"resources":{"requests":{"storage":"'$size'"}}}}'
  # Copy data from old PVC to temp PVC
  cat <<<"$jobtemplate" |
    sed s/NAMESPACE/$NAMESPACE/ |
    sed s/PVC/$pvc/ |
    kubectl apply -f -
  kubectl wait --for=condition=complete --timeout=86400s job/migrate-job -n $NAMESPACE
  kubectl logs --tail=-1 -l job-name=migrate-job -n $NAMESPACE >$WORKDIR/logs/$pvc
  kubectl delete job migrate-job -n $NAMESPACE
  # Delete but save old PVC
  oldpv=$(kubectl get pvc $pvc -n $NAMESPACE -o jsonpath='{.spec.volumeName}')
  kubectl get pvc $pvc -n $NAMESPACE -o yaml >$WORKDIR/pvc/$pvc.yml
  kubectl delete pvc $pvc -n $NAMESPACE
  # Delete temp PVC
  newpv=$(kubectl get pvc px-migration-temp -n $NAMESPACE -o jsonpath='{.spec.volumeName}')
  kubectl delete pvc px-migration-temp -n $NAMESPACE
  # Delete but save old PV
  kubectl get pv $oldpv -o yaml >$WORKDIR/pv-old/$oldpv.yml
  kubectl delete pv $oldpv
  # Rename Portworx volume
  pxctl volume clone --name $oldpv $newpv
  pxctl volume delete $newpv -f
  # Rename temp PV to old PV
  kubectl get pv $newpv -o yaml | sed "s/^  name: .*/  name: $oldpv/;s/^    volumeID.*/    volumeID: $oldpv/" >$WORKDIR/pv-new/$oldpv.yml
  kubectl delete pv $newpv
  kubectl apply -f $WORKDIR/pv-new/$oldpv.yml
  kubectl patch pv $oldpv --type=json -p="[{'op': 'remove', 'path': '/spec/claimRef'}]"
  # Apply old PVC
  sed 's#volume.beta.kubernetes.io/storage-class: .*#volume.beta.kubernetes.io/storage-class: px-migrated#;s/storageClassName: .*/storageClassName: px-migrated/' $WORKDIR/pvc/$pvc.yml | kubectl apply -f -
done

# Clean up
kubectl delete sc portworx-sc
