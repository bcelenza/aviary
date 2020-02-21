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
