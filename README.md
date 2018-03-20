# k8s-installer

_Note: This project is under active developement_

Install the Armory Platform on Kubernetes

## How it works
The install script will prompt for information about the environment and then use templated manifests to install the platform.

## Challenges
### Configuration
Right now the configurator is backed by S3 and fetched at runtime. Since our early users are all in on GKE we will probably have to back this by something else (eg GCS). Also, the pattern of fetching config when the program starts isn't really the 'k8s way'. It would be more idiomatic to deploy a config map and then mount it to the application at deploy time.

### Redeploying
The ideal way to redeploy would be to use the k8s-v2 provider. Then we can easily apply versioned config changes. The only difficulty is interacting with lighthouse to determine if there are any running Orca tasks and scaling down old server-groups.

### Redis
The user should be able to specify their own Redis cluster. If not we will run Redis with 1-2 read-slaves and redis-sentinel. As outlined [here](http://jeffmendoza.github.io/kubernetes/v1.1/examples/redis/README.html).


### Security
The platform will be in its own namespace to keep it isolated from other applications in the cluster.