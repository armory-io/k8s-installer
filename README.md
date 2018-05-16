# k8s-installer

Install the Armory Platform on Kubernetes

## How does it work?

1. Clone this repo.
2. Check out the desired tag.
2. Execute `src/install.sh`
3. Follow the directions.


## Working on the installer
Here are some helpful commands while you're developing on the installer.
```bash
# run the install script with namespaced resources (for easier cleanup and namespaces for multiple developers)
NAMESPACE="yournamehere-$(date -u +"%m%dt%H%M")" ./src/install.sh

# find your latest created namespace
myLatestCreatedNamespace() {
  kubectl get namespaces --sort-by="{.metadata.creationTimestamp}" | grep yournamehere | tail -1 | awk "{print \$1}"
}
export -f myLatestCreatedNamespace


# keep an eye out on the latest containers
watch -n 1  'kubectl -n $(myLatestCreatedNamespace) get pods'

# keep an eye out on 
watch -n 1 'kubectl -n $(myLatestCreatedNamespace) logs -l app=dinghy'
```


## Pinning versions
By default, we're always going to be fetching `stable` Armory versions. If you want to pin it to a specific version,
you'll need to add it to src/version.manifest. 
Example: 
```bash
$ ls -la src/
 $ ls -la src/
 drwxr-xr-x 10 kevinawoo staff   320 May 11 15:22 ./
 drwxr-xr-x 13 kevinawoo staff   416 May 11 15:25 ../
 -rwxr-xr-x  1 kevinawoo staff 44939 May 11 15:22 install.sh*
 -rw-r--r--  1 kevinawoo staff  1457 May 11 14:01 version.manifest  <--- this is a pinned version.manifest
 ...
```

You can find the contents of your current version.manifest in `src/build/version.manifest` after the script has been ran once.


## Running edge or stable builds
By default, this script will run on stable releases of Armory.
Edge builds are internal Armory builds that require access to our Jenkins.
Try running the script, if you get an error reaching jenkins, [go here](https://github.com/armory-io/command#configuration) then rerun.

For more info, see:
```bash
./src/install.sh --help
```
