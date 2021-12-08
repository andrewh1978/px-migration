NAMESPACE=postgres
STORAGECLASS=portworx-sc
SUFFIX=px

JQ="docker run -i --rm --name jq endeveit/docker-jq jq"

# FIXME get original number of replicas for each deployment/statefulset

# Scale deployments and statefulsets to zero
kubectl scale deployments --all --replicas 0 -n $NAMESPACE
kubectl scale sts --all --replicas 0 -n $NAMESPACE

# Get list of PVCs
pvcs_sts=$(kubectl get sts -n $NAMESPACE -o jsonpath='{.items[*].spec.volumeClaimTemplates[*].metadata.name}' 2>/dev/null)
pvcs_deploy=$(kubectl get deploy -n $NAMESPACE -o jsonpath='{.items[*].spec.template.spec.volumes[*].persistentVolumeClaim.claimName}' 2>/dev/null)
PVCs="$pvcs_sts $pvcs_deploy"

# Get list of deployments
DEPLOYMENTS=$(kubectl get deploy -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

# Get list of statefulsets
STATEFULSETS=$(kubectl get sts -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

# Create new PVCs
for pvc in $PVCs; do
  # FIXME also get accessmodes and labels
  size=$(kubectl get pvc $pvc -n $NAMESPACE -o jsonpath='{.spec.resources.requests.storage}')
  cat portworx-pvc.yml.template |
    sed s/STORAGECLASS/$STORAGECLASS/ |
    sed s/NAMESPACE/$NAMESPACE/ |
    sed s/PVC/$pvc-$SUFFIX/ |
    sed s/SIZE/$size/ |
    kubectl apply -f -
done

# Run migration jobs
for pvc in $PVCs; do
  cat migrate-job.yml.template |
    sed s/NAMESPACE/$NAMESPACE/ |
    sed s/PVC/$pvc/ |
    sed s/SUFFIX/$SUFFIX/ |
    kubectl apply -f -
  kubectl wait --for=condition=complete --timeout=86400s job/migrate-job -n $NAMESPACE
  kubectl delete job migrate-job -n $NAMESPACE
done

# Patch deployments for new PVCs
for deployment in $DEPLOYMENTS; do
  # Get number of PVCs
  n=$(kubectl get deploy $deployment -n $NAMESPACE -o json | $JQ -r '.spec.template.spec.volumes[].name' | wc -l)
  for i in $(seq 1 $n); do
    # Get PVC name
    pvc=$(kubectl get deploy $deployment -n $NAMESPACE -o jsonpath='{.spec.template.spec.volumes[0].persistentVolumeClaim.claimName}')
    kubectl patch deploy $deployment -n $NAMESPACE --type='json' -p '[{"op":"replace","path":"/spec/template/spec/volumes/'$[$i-1]'/persistentVolumeClaim/claimName","value":"'$pvc-$SUFFIX'"}]'
  done
done

# FIXME repeat for statefulsets
