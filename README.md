# What

This will migrate some PVCs to Portworx volumes

# How

1. Scale down any applications using the PVCs to be migrated.

2. Edit `migrate.sh` - set `NAMESPACE` for the namespace containing the PVCs, and check the `LABEL` is acceptable.

3. Label the PVCs to be migrated to match `LABEL` in step 2:
```
kubectl label pvc <pvc> -n <namespace> px/migrate=true
kubectl label pvc --all -n <namespace> px/migrate=true
```

4. Run the migration:
```
sh migrate.sh
```

5. Scale up your applications

# Example

You can install Ondat (formerly known as StorageOS) and provision a PostgreSQL running on top, and migrate that PostgreSQL to Portworx:
```
sh install-ondat.sh
kubectl apply -f ondat-postgres.yml
kubectl scale deploy postgres -n postgres --replicas 0
kubectl label pvc postgres-ondat -n postgres px/migrate=true
sh migrate.sh
kubectl scale deploy postgres -n postgres --replicas 1
```
