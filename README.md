# moodle-single-node-azure
Deploys Moodle 3.11.12 on a single node on Azure Cloud.

# Description
This project deploys the following Azure resources:
- Virtual Network and its Subnets
- Network Security Groups
- Application Gateway and its Public IP
- Virtual Machine and its OS/Data Disks and Network Card
- Postgres Database
- Recovery Service Vault and its Daily Backup Policy and Protected Item (VM backup)
- Bastion and its Public IP
- Log Analytics Workspace (for database, Application Gateway logs)
- Storage Accounts (for Web Server metrics)

And installs the following software (up to their latest available patch level for the linux distro) on the virtual machine:
- Ubuntu 20.04
- Postgres client 12
- Unzip 6.00
- PHP Client 7.4
- Apache2 2.4
- Redis 5.0
- PHP 7.4 modules
  - php7.4-curl
  - php7.4-gd
  - php7.4-intl
  - php7.4-ldap
  - php7.4-mbstring
  - php7.4-pgsql
  - php7.4-pspell
  - php7.4-redis
  - php7.4-soap
  - php7.4-xml
  - php7.4-xmlrpc
  - php7.4-zip

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
1. Create a new file named _azure/arm-templates/deploy-resources.parameters.json_ based on the _azure/arm-templates/deploy-resources.parameters.example.json_ file.
1. Edit the new _deploy-resources.parameters.json_ file to your liking.
1. Authenticate your Azure Client to your Azure subscription by running the `az login` command.
1. Adapt and run the following commands from a bash shell (linux):
    ```
    deployment_name="MoodleManualDeployment"
    parameter_file="azure/arm-templates/deploy-resources.parameters.json"
    resource_group_name="[Your resource Group name]"
    template_file="azure/arm-template/deploy-resources.json"

    az deployment group create \
      --name "${deployment_name}" \
      --parameter @"${parameter_file}" \
      --resource-group "${resource_group_name}" \
      --template-file "${template_file}" \
      --verbose
    ```

Enjoy!