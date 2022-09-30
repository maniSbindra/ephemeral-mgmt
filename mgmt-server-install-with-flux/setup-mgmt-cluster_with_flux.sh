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
# FLUX_BOOTSTRAP_REPOSITORY=""
# GITHUB_INFRA_REPOSITORY=""
. ./.env

# Create new kind cluster
echo "Creating new kind cluster"
kind create cluster --image kindest/node:v1.23.0 --name crossplane-mgmt-eph-flux

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
sleep 60

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

# Bootstrap flux
flux bootstrap git \
  --token-auth=true \
  --url=${FLUX_BOOTSTRAP_REPOSITORY} \
  --password=${GITHUB_TOKEN} \
  --branch=main \
  --verbose  

# Create Flux Source for infrastructure repo
flux create source git infra-repo-public \
--url ${GITHUB_INFRA_REPOSITORY} \
--branch "main" \
--username=${GITHUB_USER} --password=${GITHUB_TOKEN}

# Install controller along with namespace, CRD, service account, role, and role binding 
kubectl apply -f install-controller.yaml

# Create Namespace for PR helm releases
kubectl create ns pr-helm-releases

# Setup Github secret for ephemeral controller
kubectl create secret generic tokensecret -n default --from-literal=token=$GITHUB_TOKEN

# Setup Github secret for flux repository
kubectl create secret generic ghtoken -n flux-system --from-literal=username=${GITHUB_USER} --from-literal=password=$GITHUB_TOKEN

# Create Image pull secret to pull container image
# kubectl create secret docker-registry ghcrpullscr -n pr-ephemeral-env-controller-system --docker-server="ghcr.io" --docker-username=$HELM_OCI_REGISTRY_USER --docker-password=$HELM_OCI_REGISTRY_PASSWORD --docker-email=mani@test.com

# Create CRD to observe APP repository PRs
kubectl apply -f ephemeral-prcontroller-CR.yaml

# Delete Kind Cluster
# kind delete cluster  --name crossplane-mgmt-eph-flux
