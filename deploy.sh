#!/usr/bin/env bash
set -e

function get_az_public_subnet() {
    local vpc_name="$1"
    local region="$2"
    local vpc_id=$(aws ec2 describe-vpcs --region "$region" --filters "Name=tag:Name,Values=$vpc_name" --query 'Vpcs[0].VpcId' --output text)
    local az_public_subnet=$(aws ec2 describe-subnets --region "$region" --filters "Name=vpc-id,Values=$vpc_id" "Name=map-public-ip-on-launch,Values=true" --query 'Subnets[0].AvailabilityZone' --output text)
    echo "$az_public_subnet"
}

function createNodeGroups {
    ACTION=$1
    read -p "Are you sure you want to $ACTION NODES in the CLUSTER ${CLUSTER_NAME} in REGION ${AWS_REGION}? (y/n): " confirm
    if [[ $confirm == [Yy] ]]; then
        ######################### GPU NODES #########################
        # Read the YAML file and convert it to a JSON string
        instance_json=$(python -c 'import sys, yaml, json; json.dump(yaml.safe_load(sys.stdin), sys.stdout, indent=4)' <instance_list.yaml)
        echo "nodegroup_type" >$CLUSTER_NAME-nodes.yaml
        # Loop through the JSON array and populate the variables
        length=$(echo $instance_json | jq '.instances | length')
        for ((i = 0; i < $length; i++)); do
            export FAMILY=$(echo $instance_json | jq -r ".instances[$i].family")
            INSTANCE_TYPE=$(echo $instance_json | jq -r ".instances[$i].instance_type")
            export SPOT_PRICE=$(echo $instance_json | jq -r ".instances[$i].spot_price")
            nodegroup_type=$(echo $instance_json | jq -r ".instances[$i].nodegroup_type")

            # Split instance_type into spot and ondemand
            IFS=',' read -ra types <<<"$INSTANCE_TYPE"
            for type in "${types[@]}"; do

                # Check if instance family exist in the AZ
                # if aws ec2 describe-instance-type-offerings \
                #     --location-type availability-zone \
                #     --filters Name=instance-type,Values=$FAMILY \
                #     --query "InstanceTypeOfferings[?Location=='$AWS_AVAILABILITY_ZONE'].InstanceType" \
                #     --output text | grep -q $FAMILY; then

                export NODEGROUP_TYPE=$nodegroup_type-$type
                echo "##################### $ACTION node: $FAMILY - $type"
                echo "##########################################"
                echo "Family:" $FAMILY
                echo "Spot Price:" $SPOT_PRICE
                echo "Nodegroup Type:" $NODEGROUP_TYPE
                echo "- $NODEGROUP_TYPE" >>$CLUSTER_NAME-nodes.yaml

                # Create nodeGroups for the cluster
                if [ "$ACTION" == "create" ]; then
                    envsubst <nodeGroups_gpu_$type.yaml | eksctl create nodegroup -f -
                elif [ "$ACTION" == "delete" ]; then
                    envsubst <nodeGroups_gpu_$type.yaml | eksctl delete nodegroup --approve -f -
                fi
                # else
                #     echo "Instance type $FAMILY is NOT available in $AWS_AVAILABILITY_ZONE"
                # fi
            done
        done
        ######################### CPU NODES #########################
        if [ "$ACTION" == "create" ]; then
            envsubst <nodeGroups_cpu_workers.yaml | eksctl create nodegroup -f -
        elif [ "$ACTION" == "delete" ]; then
            envsubst <nodeGroups_cpu_workers.yaml | eksctl delete nodegroup --approve -f -
        fi
    fi
}

function createCluster {
    read -p "Are you sure you want to CREATE a CLUSTER ${CLUSTER_NAME} in REGION ${AWS_REGION}? (y/n): " confirm
    if [[ $confirm == [Yy] ]]; then
        # Create cluster
        envsubst <cluster.yaml | eksctl create cluster -f -

        # Create ASG policy
        envsubst <policy.template.json >policy.json
        aws iam create-policy --policy-name ${AWS_POLICY_NAME} --policy-document file://policy.json

        # Create CPU node
        envsubst <nodeGroups_cpu.yaml | eksctl create nodegroup -f -

        # Get cluster credentials
        aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME}
        kubectl cluster-info

        # Install eb-csi addons
        kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=master"
        kubectl get pods -n kube-system | grep ebs-csi

        # Metricts server
        kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
        kubectl get pods -n kube-system | grep metrics-server

        # Install autoscaler
        envsubst <asg-autodiscover.yaml | kubectl apply -f -
        kubectl get pods --namespace=kube-system | grep autoscaler

        # Update aws-auth
        kubectl get configmap aws-auth -n kube-system -o yaml >aws-auth.yaml
        echo "Update manually aws-auth.yaml, use as example mapUsers.yaml"
        echo "kubectl apply -f aws-auth.yaml"
    fi

}

function deleteCluster {
    read -p "Are you sure you want to DELETE the CLUSTER ${CLUSTER_NAME} in REGION ${AWS_REGION}? (y/n): " confirm
    if [[ $confirm == [Yy] ]]; then
        eksctl delete cluster --region=${AWS_REGION} --name=${CLUSTER_NAME}
        aws iam delete-policy --policy-arn ${AWS_POLICY_ARN}
    fi
}

### Main
export ENVIRONMENT=$1
export AWS_REGION=$2
export ACTION=$3
export AWS_PARTITION="aws"
export CLUSTER_NAME="devseed-k8s-${ENVIRONMENT}"
export KUBERNETES_VERSION="1.27"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export AWS_POLICY_NAME=devseed-k8s_${ENVIRONMENT}-${AWS_REGION}
export AWS_POLICY_ARN=arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${AWS_POLICY_NAME}
export VPC_NAME="eksctl-${CLUSTER_NAME}-cluster/VPC"
# export AWS_AVAILABILITY_ZONE=us-east-1f
export AWS_AVAILABILITY_ZONE=$(get_az_public_subnet $VPC_NAME $AWS_REGION)
echo "Make sure you have created a Key pairs, called: k8s-sam-${AWS_REGION}..."
ACTION=${ACTION:-default}
if [ "$ACTION" == "create_cluster" ]; then
    createCluster
elif [ "$ACTION" == "delete_cluster" ]; then
    deleteCluster
elif [ "$ACTION" == "create_nodes" ]; then
    # Create GPU nodes
    createNodeGroups create
elif [ "$ACTION" == "delete_nodes" ]; then
    # Delete GPU nodes
    createNodeGroups delete
else
    echo "The action is unknown."
fi
