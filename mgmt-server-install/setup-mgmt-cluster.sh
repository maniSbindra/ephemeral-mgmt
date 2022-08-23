#!/bin/bash

# The script below assumes that kind, helm, kubectl , kubectl crossplane plugin, and argocd CLI are installed on the machine
# 1. rename .env-template.sh to .env, and fill in the values of the variables
# 2. Create creds.json file in the same directory as this script 'az ad sp create-for-rbac --role Contributor --scopes /subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx > "creds.json"'

set -o errexit
set -o nounset
set -o pipefail

# Following variables are required to be set in .env file
# HELM_OCI_REGISTRY_USER=
# HELM_OCI_REGISTRY_PASSWORD=""
# POSTGRES_DB_PASSWORD=""
# GITHUB_USER=
# GITHUB_TOKEN=""
# GITHUB_APP_REPOSITORY=""
# GITHUB_INFRA_REPOSITORY=""
. ./.env

# Create new kind cluster
echo "Creating new kind cluster"
kind create cluster --image kindest/node:v1.23.0 --name crossplane-mgmt-fmreal

# Install crossplane
echo "Installing crossplane"
kubectl create namespace crossplane-system

# install crossplane components
echo "Installing crossplane components"
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update
helm install crossplane --namespace crossplane-system crossplane-stable/crossplane
# kubectl get all -n crossplane-system

# wait for crosplane to be ready
echo "Waiting for crossplane to be ready"
sleep 30

# for next 2 commands kubectl crossplane extension needs to be installed
# Install crossplane Azure Jet Provider
echo "Installing crossplane Azure Jet Provider"
kubectl crossplane install provider crossplane/provider-jet-azure:v0.9.0
# Install crossplane helm provider
echo "Installing crossplane helm provider"
kubectl crossplane install provider crossplane/provider-helm:master

# watch kubectl get pkg
# wait for crossplane packages to be ready
echo "Waiting for crossplane packages to be ready"
sleep 30

# create secrets required
echo "Creating required secrets"
kubectl create secret generic psql-password -n crossplane-system --from-literal=password=$POSTGRES_DB_PASSWORD

# create creds.json file using script 'az ad sp create-for-rbac --role Contributor --scopes /subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx > "creds.json"'
kubectl create secret generic azure-creds -n crossplane-system --from-file=creds=./creds.json
kubectl create secret generic helmoci -n crossplane-system --from-literal=username=$HELM_OCI_REGISTRY_USER --from-literal=password=$HELM_OCI_REGISTRY_PASSWORD

# Setup Argocd
echo "Setting up Argocd"
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# wait for argocd to be ready
echo "Waiting for argocd to be ready"
sleep 120

# login into argocd
echo "Logging into argocd"
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
ARGOCD_ADMIN_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo)
argocd login localhost:8080 --username admin --password $ARGOCD_ADMIN_PASS --insecure


# Add app and infra repos to argocd Repositories to Argocd
echo "Adding app and infra repos to argocd Repositories"
argocd repo add $GITHUB_APP_REPOSITORY --username $GITHUB_USER --password $GITHUB_TOKEN
argocd repo add $GITHUB_INFRA_REPOSITORY --username $GITHUB_USER --password $GITHUB_TOKEN


# Apply application set with pull request builder
echo "Applying application set with pull request builder"
kubectl apply -f ./argo-app-set.yaml


# Delete Kind Cluster
# kind delete cluster  --name crossplane-mgmt-fmreal
