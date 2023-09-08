# DevSeed k8s GPU cluster

This script utilizes eksctl to deploy a Kubernetes cluster that is equipped with GPU support. In addition, it allows users to choose between Spot and On-Demand instances. Once the cluster is up, it also prepares the environment for deploying Helm charts.

e.g: https://github.com/developmentseed/ds-helm-chart

# Deploy a cluster

```sh
./deploy.sh <enviroment> <aws_region> create
# e.g
./deploy.sh staging us-west-1 create
```


# Delete a cluster

```sh
./deploy.sh <enviroment> <aws_region> delete
# e.g
./deploy.sh staging us-west-1 delete
```