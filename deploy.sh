#!/usr/bin/env bash
set -e

export ENVIRONMENT=$1
export AWS_REGION=$2
export ACTION=$3
export AWS_AVAILABILITY_ZONE=$(aws ec2 describe-availability-zones --region $AWS_REGION --query 'AvailabilityZones[0].ZoneName' --output text)
export AWS_PARTITION="aws"
export CLUSTER_NAME="devseed-k8s-${ENVIRONMENT}"
export KUBERNETES_VERSION="1.27"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export AWS_POLICY_NAME=devseed-k8s_${ENVIRONMENT}
export AWS_POLICY_ARN=arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${AWS_POLICY_NAME}

function createPolicy {
    POLICY_ARN=$(aws iam list-policies --query 'Policies[?PolicyName==`'${AWS_POLICY_NAME}'`].Arn' --output text)
    if [ "$POLICY_ARN" != "$AWS_POLICY_ARN" ]; then
        envsubst <policy.template.json >policy.json
        aws iam create-policy --policy-name ${AWS_POLICY_NAME} --policy-document file://policy.json
        rm policy.json
    else
        echo "Policy ${AWS_POLICY_NAME} already exist."
    fi
}

function createNodeGroups {
    ACTION=$1
    instance_list=(
        # "g4ad.xlarge,0.2"
        # "g4ad.8xlarge,1.1"
        # "g4ad.16xlarge,2.3"
        "g5.xlarge,0.5"
        "g5.2xlarge,0.6"
        "g5.4xlarge,1.5"
    )
    for instance_info in "${instance_list[@]}"; do
        IFS=',' read -ra INFO <<<"$instance_info"
        export INSTANCE_TYPE="${INFO[0]}"
        export PRICE="${INFO[1]}"
        export INSTANCE_TYPE_NAME="${INSTANCE_TYPE//./-}"

        if [ "$ACTION" == "create" ]; then
            # Check whether a given instance type is available in a given AZ
            if aws ec2 describe-instance-type-offerings \
                --location-type availability-zone \
                --filters Name=instance-type,Values=$INSTANCE_TYPE \
                --query "InstanceTypeOfferings[?Location=='$AWS_AVAILABILITY_ZONE'].InstanceType" \
                --output text | grep -q $INSTANCE_TYPE; then

                #### Create nodeGroups for the cluster
                envsubst <nodeGroups_gpu_spot.yaml | eksctl create nodegroup -f -
                envsubst <nodeGroups_gpu_ondemand.yaml | eksctl create nodegroup -f -

            else
                echo "Instance type $INSTANCE_TYPE is NOT available in $AWS_AVAILABILITY_ZONE"
            fi
        elif [ "$ACTION" == "delete" ]; then
            envsubst <nodeGroups_gpu_spot.yaml | eksctl delete nodegroup --approve -f -
        fi
    done
}

function createCluster {
    read -p "Are you sure you want to create a cluster ${CLUSTER_NAME} in region ${AWS_REGION}? (y/n): " confirm
    if [[ $confirm == [Yy] ]]; then
        ### Create cluster
        envsubst <cluster.yaml | eksctl create cluster -f -

        #### Create ASG policy
        createPolicy

        #### Create CPU node
        envsubst <nodeGroups_cpu.yaml | eksctl create nodegroup -f -

        # Create GPU nodes
        createNodeGroups create

        ### Get cluster credentials
        aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME}
        kubectl cluster-info

        #### Install eb-csi addons
        kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=master"
        kubectl get pods -n kube-system | grep ebs-csi

        #### Metricts server
        kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
        kubectl get pods -n kube-system | grep metrics-server

        ## Install autoscaler
        envsubst <asg-autodiscover.yaml | kubectl apply -f -
        kubectl get pods --namespace=kube-system | grep autoscaler

        #### Update aws-auth
        kubectl get configmap aws-auth -n kube-system -o yaml >aws-auth.yaml
        echo "Update manually aws-auth.yaml, use as example mapUsers.yaml"
        echo "kubectl apply -f aws-auth.yaml"
    fi

}

function deleteCluster {
    read -p "Are you sure you want to delete the cluster ${CLUSTER_NAME} in region ${AWS_REGION}? (y/n): " confirm
    if [[ $confirm == [Yy] ]]; then
        eksctl delete cluster --region=${AWS_REGION} --name=${CLUSTER_NAME}
        createNodeGroups delete
        aws iam delete-policy --policy-arn ${AWS_POLICY_ARN}
    fi
}

### Main
ACTION=${ACTION:-default}
if [ "$ACTION" == "create" ]; then
    createCluster
elif [ "$ACTION" == "delete" ]; then
    deleteCluster
else
    echo "The action is unknown."
fi
