#!/bin/sh

set -e

# Create cluster
eksctl create cluster --fargate --name aviary
# Create fargate profile for aviary namespace
eksctl create fargateprofile --namespace aviary --cluster aviary --name fp-aviary
# Creat an IAM OIDC provider
eksctl utils associate-iam-oidc-provider --cluster aviary --approve
# Setup desired policy before
eksctl create iamserviceaccount --name aviary-pods --namespace aviary --cluster aviary --attach-policy-arn arn:aws:iam::027496699299:policy/Aviary-Pods --approve --override-existing-serviceaccounts

# Setup EC2 nodegroup for appmesh-system namespace (permanent storage required)
eksctl create nodegroup --cluster aviary -f appmesh-system/nodegroup.yaml

# Helm Charts
# Add the EKS charts repo
helm repo add eks https://aws.github.io/eks-charts
# Add injector
helm upgrade -i appmesh-inject eks/appmesh-inject --namespace appmesh-system
# Add controller
helm upgrade -i appmesh-controller eks/appmesh-controller --namespace appmesh-system
# Add prometheus
helm upgrade -i appmesh-prometheus eks/appmesh-prometheus --namespace appmesh-system --set retention=12h --set persistentVolumeClaim.claimName=prometheus

# External DNS
PolicyARN=$(aws iam create-policy \
    --policy-name ExternalDNSPolicy \
    --policy-document file://external-dns-policy.json \
    | jq -r ".Policy.Arn")
eksctl create iamserviceaccount \
    --cluster=aviary \
    --namespace=appmesh-system \
    --name=external-dns-controller \
    --attach-policy-arn=$PolicyARN \
    --override-existing-serviceaccounts \
    --approve
kubectl apply -f appmesh-system/external-dns.yaml

# ALB Ingress
kubectl apply -f appmesh-system/alb-rbac-role.yaml
PolicyARN=$(aws iam create-policy \
    --policy-name ALBIngressControllerIAMPolicy \
    --policy-document https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.1.4/docs/examples/iam-policy.json \
    | jq -r ".Policy.Arn")
eksctl create iamserviceaccount \
    --cluster=aviary \
    --namespace=appmesh-system \
    --name=alb-ingress-controller \
    --attach-policy-arn=$PolicyARN \
    --override-existing-serviceaccounts \
    --approve
kubectl apply -f appmesh-system/ingress-controller.yaml

# Chaos!
helm install chaoskube stable/chaoskube --set dryRun=false,namespaces='!kube-system\,!appmesh-system',interval=5m,rbac.create=true
