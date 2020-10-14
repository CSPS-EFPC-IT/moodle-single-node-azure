# moodle-single-node-azure
Deploys Moodle Application on Azure Cloud.

# Description
This project deploys the following Azure resources:
- Virtual Network
- Network Security Groups
- Application Gateway and Public IP
- Public IP
- Virtual Machine and Data Disk
- Postgres Database
- Recovery Vault
- Bastion

# Prerequisites

## Tools
1. Azure client (a.k.a az cli)
1. Text editor
1. Linux client or emulator

## Azure Ressources
1. An Azure subscription.
1. A target resource group.
1. A Key Vault with a properly signed SSL/TLS Certificate for the new moodle instance.
1. A User Assigned Managed Identity (UAMI).
1. Optional - A custom domain name for the new moodle instance.

## Authorizations
1. Permission to manage (CRUD) resources in the target resource group.
1. GET and LIST permissions on the Key Vault Secrets granted to the User Assigned Managed Identity. This will allow the Application Gateway to retrieve the SSL/TLS certificate private key from the Key Vault using the UAMI .

# Usage
1) Clone this projet.
1) Create a new file named *armTemplates/azureDeploy.parameters.json* based on the *armTemplates/azureDeploy.parameters.example.json* file.
1) Edit the new _azureDeploy.parameters.json_ file to your need.
1) Adapt and run the following commands:\
`deploymentName="MyDeploymentPart1"`\
`resourceGroupName="[Your resource Group name]"`\
`templateFile="armTemplate/azureDeploy.json"`\
`parameterFile="armTemplates/azureDeploy.parameters.json"`\
`az deployment group create --name $deploymentName --resource-group $resourceGroupName --template-file $templateFile --parameter @$parameterFile --verbose`