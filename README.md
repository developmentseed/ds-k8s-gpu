# DevSeed k8s cluster with GPU nodes

This is a lab project aimed at providing easy access to GPU instances for machine learning engineers. The script uses eksctl to deploy a Kubernetes cluster that is equipped with GPU support. In addition, it allows users to choose between Spot and On-Demand instances. Once the cluster is up and running, it also prepares the environment for deploying Helm charts.

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

Once you have created your nodes, you will have a file called `devseed-k8s-<enviroment>-nodes.yaml`, which will contain the available nodegroup_type for you to use to deploy the helm charts.


## Using Persistence Disk

If you plan to use persistent disks, make sure to first check the availability zone where your nodes are created. e.g: `us-east-1b` then:

```sh
aws ec2 create-volume \
  --region us-east-1 \
  --availability-zone us-east-1b \
  --size 20 \
  --volume-type gp2 \
  --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=devseed-ebs-test}]'
```

Copy the `VolumeId` and add in the `values.yaml` file
