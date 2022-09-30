# Installation and Setup

The script [setup-mgmt-cluster_with_flux.sh](https://github.com/maniSbindra/ephemeral-mgmt/blob/main/mgmt-server-install-with-flux/setup-mgmt-cluster_with_flux.sh) is used to setup the management cluster. Following are the prerequisites before installing this script:

## Pre-requisites

* Kind is setup on your machine
* kubectl client is installed
* helm client is installed
* kubectl crossplane plugin is installed: You can refer steps mentioned at [install crossplane](https://crossplane.io/docs/v1.9/getting-started/install-configure.html)
* Flux CLI is installed : [Install Flux CLI](https://fluxcd.io/flux/installation/)
* Additionally we also need to create creds.json file in the same directory as the script using the command.
    ```
    az ad sp create-for-rbac --role Contributor --scopes /subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx > "creds.json"
    ```
  This service principal is used by the Crossplane Azure jet provider to provision Azure resource. For more information regarding the service principal creation please see the [crossplane documentation](https://crossplane.io/docs/v1.9/getting-started/install-configure.html#get-azure-principal-keyfile)

## Setup the Management Cluster

* Clone the repo 

  ```
  git clone https://github.com/maniSbindra/ephemeral-mgmt.git
  ```

* Give script execute permissions
  ```
  cd mgmt-server-install-with-flux
  chmod +x setup-mgmt-cluster_with_flux.sh
  ```

* Set values of environment variables : copy the file .env-template.sh to .env. Then set the values of the variables in the .env file. These variables (with sample values) are:
  * HELM_OCI_REGISTRY_USER and HELM_OCI_REGISTRY_PASSWORD: This Github token needs to have permissions to read Helm charts published by the Application Repository (through github workflow in application repository)
  * POSTGRES_DB_PASSWORD: This will be used as the admin password for all ephemeral Postgres SQL Databases (one for each PR) created 
  * GITHUB_USER & GITHUB_TOKEN: This Github token will be used by the setup script to add a flux source for the infrastructure repository
  * GITHUB_INFRA_REPOSITORY: https://github.com/maniSbindra/ephemeral-env-infra.git  
  * FLUX_BOOTSTRAP_REPOSITORY: https://github.com/Your-Flux-Bootstrap-Repository 

* Execute the script: next we execute the script
  
   ```
   ./setup-mgmt-cluster_with_flux.sh
   ```
   This script should take around 4-5 minutes to execute. The last setup of this script creates a [custom resource](https://github.com/maniSbindra/ephemeral-mgmt/blob/main/mgmt-server-install-with-flux/ephemeral-prcontroller-CR.yaml) which our custom ephemeral environment controller monitors. This is the script where the name of the custom resource, the Gitub repository to monitor etc are set, see the "Ephemeral environment PR controller CRD specification" section for details on all fields. 
   
## Validate the Management Cluster setup

Next we validate that the management server installation is successful.

### Check that Argo CD and Crossplane controllers are running in the Management Cluster


Execute "kubectl get pods -A". This should show Crossplane (Azure Jet Provider and Helm Provider controllers) and our custom controller running in the kubebuilder-system namespace as shown below

  ```
  $ kubectl get pods -A                                                                                                                            
  NAMESPACE            NAME                                                             READY   STATUS    RESTARTS   AGE
  crossplane-system    crossplane-6f6488b745-nxm7t                                      1/1     Running   0          3h24m
  crossplane-system    crossplane-provider-helm-19a2e442342c-7dc6468f8b-vq5hn           1/1     Running   0          3h23m
  crossplane-system    crossplane-provider-jet-azure-000558e62129-68cdf6654-jjrwj       1/1     Running   0          3h23m
  crossplane-system    crossplane-rbac-manager-665757f749-4ndfw                         1/1     Running   0          3h24m
  flux-system          helm-controller-7f4cb5648c-wxb2j                                 1/1     Running   0          3h22m
  flux-system          kustomize-controller-76fdc7df8b-76m7b                            1/1     Running   0          3h22m
  flux-system          notification-controller-75b7fbd7fd-d8swk                         1/1     Running   0          3h22m
  flux-system          source-controller-f5c5ff8b8-sv9bj                                1/1     Running   0          3h22m
  kube-system          coredns-64897985d-f9hxs                                          1/1     Running   0          3h24m
  kube-system          coredns-64897985d-mnwnh                                          1/1     Running   0          3h24m
  kube-system          etcd-crossplane-mgmt-eph-flux-control-plane                      1/1     Running   0          3h24m
  kube-system          kindnet-62v7m                                                    1/1     Running   0          3h24m
  kube-system          kube-apiserver-crossplane-mgmt-eph-flux-control-plane            1/1     Running   0          3h24m
  kube-system          kube-controller-manager-crossplane-mgmt-eph-flux-control-plane   1/1     Running   0          3h24m
  kube-system          kube-proxy-z5smp                                                 1/1     Running   0          3h24m
  kube-system          kube-scheduler-crossplane-mgmt-eph-flux-control-plane            1/1     Running   0          3h24m
  kubebuilder-system   kubebuilder-controller-manager-59f9c57c84-jlpgx                  2/2     Running   0          3h22m
  local-path-storage   local-path-provisioner-5bb5788f44-4rkrf                          1/1     Running   0          3h24m
  ```

#### Verify that the infra repository has been added as a flux source 

* Verify that infra repository has been added as a source by flux by executing the command "flux get sources git". The output should be similar to
  
  ```
  $ flux get sources git                                                                                                      
  NAME                    REVISION        SUSPENDED       READY   MESSAGE                                                                      
  flux-system             main/9d6b48f    False           True    stored artifact for revision 'main/9d6b48f7f5456b067c0860788b8fb2021ba28c40'
  infra-repo-public       main/9c76e72    False           True    stored artifact for revision 'main/9c76e72de74197f21798c2e6f01b3e8488ef5435'
  ```

* Verify the custom resource prcontroller has been created and is in the ready state

  ```
  $ kubectl get prcontroller -A
  NAMESPACE   NAME                  STATUS
  default     pr-eph-env-ctrlr-1   Ready
  ```