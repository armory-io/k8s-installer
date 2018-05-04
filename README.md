# k8s-installer

Install the Armory Platform on Kubernetes

## How does it work?

1. Clone this repo.
2. Check out the desired tag.
2. Execute `src/install.sh`
3. Follow the directions.


## Working on the installer
Here's some helpful commands while you're developing on the installer.
```bash
# run the install script with namespaced resources (for easier cleanup and namespaces for multiple developers)
NAMESPACE="yournamehere-$(date -u +"%m%dt%H%M")" ./src/install.sh

# find your latest created namespace
myLatestCreatedNamespace() {
  kubectl get namespaces --sort-by="{.metadata.creationTimestamp}" | grep yournamehere | tail -1 | awk "{print \$1}"
}

# keep an eye out on the latest containers
watch -n 1  'kubectl -n $(myLatestCreatedNamespace) get pods'

# keep an eye out on 
watch -n 1 'kubectl -n $(myLatestCreatedNamespace) logs -l app=dinghy'
```
