# DevSeed k8s GPU cluster

This script utilizes eksctl to deploy a Kubernetes cluster that is equipped with GPU support. In addition, it allows users to choose between Spot and On-Demand instances. Once the cluster is up, it also prepares the environment for deploying Helm charts.

e.g: https://github.com/developmentseed/ds-helm-chart

## Create/Delete a cluster

```sh
./deploy.sh <enviroment> <aws_region> create_cluster
./deploy.sh <enviroment> <aws_region> delete_cluster
```

Once you have created your cluster, the next step is to create your GPU nodes. The configuration can be found in the instance_list.yaml file, which you can modify according to the instances you require.

## Create/Delete GPU nodes

```sh
./deploy.sh <enviroment> <aws_region> create_nodes
./deploy.sh <enviroment> <aws_region> delete_nodes
```