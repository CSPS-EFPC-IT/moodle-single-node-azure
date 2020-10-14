# moodle-single-node-azure
Deploys a simple Moodle stack on Azure Cloud.

# Description
This project deploys the following Azure resources:
- Virtual Network and Subnets
- Network Security Groups
- Application Gateway and its Public IP
- Virtual Machine and its Data Disk
- Postgres Database
- Recovery Vault
- Bastion and its Public IP

And installs the following software (up to their latest available patch level for the linux distro) on the virtual machine:
- Ubuntu 18.04
- Postgres client 10
- Unzip 6.00
- PHP Client 7.2
- Apache2 2.4
- Redis 4.0
- PHP 7.2 modules
  - php7.2-pspell
  - php7.2-curl
  - php7.2-gd
  - php7.2-intl
  - php7.2-pgsql
  - php7.2-xml
  - php7.2-xmlrpc
  - php7.2-ldap
  - php7.2-zip
  - php7.2-soap
  - php7.2-mbstring
  - php7.2-redis

# Prerequisites
## Tools
1. An Azure Client (a.k.a. "az cli")
1. A Git client
1. A text editor

## Azure Ressources
1. An Azure subscription.
1. A target resource group.
1. A Key Vault with a properly signed SSL/TLS Certificate for the new moodle instance.
1. A User Assigned Managed Identity (UAMI).

## Azure Permissions
1. Permission to manage (CRUD) resources in the target resource group.
1. GET permission on the Key Vault Secrets granted to the User Assigned Managed Identity. This will allow the Application Gateway to retrieve the SSL/TLS certificate private key from the Key Vault using the UAMI .

## Other Dependencies
1. Optional - An SMTP server.
1. Optional - A custom domain name for the new moodle instance.


# Usage
1. Clone this projet.
1. Create a new file named *armTemplates/azureDeploy.parameters.json* based on the *armTemplates/azureDeploy.parameters.example.json* file.
1. Edit the new _azureDeploy.parameters.json_ file to your liking.
1. Authenticate your Azure Client to your Azure subscription by running the `az login` command and following the instructions.
1. Adapt and run the following commands (on linux):\
`deploymentName="MoodleManualDeployment"`\
`resourceGroupName="[Your resource Group name]"`\
`templateFile="armTemplate/azureDeploy.json"`\
`parameterFile="armTemplates/azureDeploy.parameters.json"`\
`az deployment group create --name $deploymentName --resource-group $resourceGroupName --template-file $templateFile --parameter @$parameterFile --verbose`

Enjoy!