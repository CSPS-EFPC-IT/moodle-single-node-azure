#!/bin/bash
#
######################################
# Delete all Moodle Single Node resources, except for the Key Vault, the User
# Assigned Managed Identity and the Application Gateway Public IP, from a given
# Resource Group. This is typically run against non-production resource groups
# to save on infrastructure costs when an environment is no longer needed.
# Globals:
#   LIBRARY_PATH - location of the sourced libraries.
# Arguments:
#   The Resource Group name containing the resources, a string.
# Outputs:
#   Writes error messages to stderr.
#   Writes trace messages to stdout.
######################################

function main() {

  # Input parameters with default value.
  declare -Ax parameters=( \
    [--resource-group-name]="" \
  )

  # Variables
  local application_gateway_ids
  local backup_item_ids
  local bastion_names
  local disk_ids
  local log_analytics_workspace_names
  local network_interface_card_ids
  local network_security_group_ids
  local postgres_server_ids
  local public_ip_ids
  local recovery_service_vault_ids
  local recovery_service_vault_names
  local storage_account_ids
  local virtual_network_ids
  local vm_ids

  # Map input parameter values.
  echo "Parsing input parameters..."
  while [[ $# -gt 0 ]]; do
    case $1 in
      --resource-group-name)
        if [[ $# -lt 2 ]]; then
          echo "Input parameter \"$1\" requires a value. Aborting."
          exit 1
        fi
        parameters[$1]="$2"
        shift 2
        ;;
      *)
        echo "Unknown input parameter: \"$1\"."
        echo "Usage: $0 ${!parameters[*]}"
        exit 1
        ;;
    esac
  done

  # Check for missing input parameters.
  for key in "${!parameters[@]}"; do
    if [[ -z "${parameters[${key}]}" ]]; then
      echo "Missing input parameter: \"${key}\". Aborting."
      echo "Usage: $0 ${!parameters[*]}"
      exit 1
    fi
    echo "Input parameter value: ${key} = \"${parameters[${key}]}\"."
  done

  # Deleting Virtual Machines, if any.
  vm_ids="$(az vm list \
      --output tsv \
      --query "[].id" \
      --resource-group "${parameters[--resource-group-name]}" \
    )"
  if [ -n "${vm_ids}" ]; then
    echo "Deleting Virtual Machines..."
    az vm delete \
      --ids "${vm_ids}" \
      --output none \
      --yes
  else
    echo "No Virtual Machine Found."
  fi

  # Deleting disks, if any.
  disk_ids="$(az disk list \
      --output tsv \
      --query "[].id" \
      --resource-group "${parameters[--resource-group-name]}" \
    )"
  if [ -n "${disk_ids}" ]; then
    echo "Deleting Disks..."
    az disk delete \
      --ids "${disk_ids}" \
      --output none \
      --yes
  else
    echo "No Disk Found."
  fi

  # Deleting Network Cards, if any.
  network_interface_card_ids="$(az network nic list \
      --output tsv \
      --query "[].id" \
      --resource-group "${parameters[--resource-group-name]}" \
    )"
  if [ -n "${network_interface_card_ids}" ]; then
    echo "Deleting Network Interface Cards..."
    az network nic delete \
      --ids "${network_interface_card_ids}" \
      --output none
  else
    echo "No Network Interface Card Found."
  fi

  # Deleting Storage Accounts, if any.
  storage_account_ids="$(az storage account list \
      --output tsv \
      --query "[].id" \
      --resource-group "${parameters[--resource-group-name]}" \
    )"
  if [ -n "${storage_account_ids}" ]; then
    echo "Deleting Storage Accounts..."
    az storage account delete \
      --ids "${storage_account_ids}" \
      --output none \
      --yes
  else
    echo "No Storage Account found."
  fi

  # Deleting Postgres Database, if any.
  postgres_server_ids="$(az postgres server list \
      --output tsv \
      --query "[].id" \
      --resource-group "${parameters[--resource-group-name]}" \
    )"
  if [ -n "${postgres_server_ids}" ]; then
    echo "Deleting Postgres Servers..."
    az postgres server delete \
      --ids "${postgres_server_ids}" \
      --output none \
      --yes
  else
    echo "No Postgres Server Found."
  fi

  # Deleting Bastion Service, if any.
  bastion_names="$(az network bastion list \
      --output tsv \
      --query "[].name" \
      --resource-group "${parameters[--resource-group-name]}" \
    )"
  if [ -n "${bastion_names}" ]; then
    echo "Deleting Bastion Services..."
    for bastion_name in ${bastion_names}; do
      az network bastion delete \
        --name "${bastion_name}" \
        --output none \
        --resource-group "${parameters[--resource-group-name]}"
    done
  else
    echo "No Bastion Service Found."
  fi

  # Deleting Application Gateways, if any.
  application_gateway_ids="$(az network application-gateway list \
      --output tsv \
      --query "[].id" \
      --resource-group "${parameters[--resource-group-name]}" \
    )"
  if [ -n "${application_gateway_ids}" ]; then
    echo "Deleting Application Gateways..."
    az network application-gateway delete \
      --ids "${application_gateway_ids}" \
      --output none
  else
    echo "No Application Gateway Found."
  fi

  # Deleting Virtual Networks.
  virtual_network_ids="$(az network vnet list \
      --output tsv \
      --query "[].id" \
      --resource-group "${parameters[--resource-group-name]}" \
    )"
  if [ -n "${virtual_network_ids}" ]; then
    echo "Deleting Virtual Networks..."
    az network vnet delete \
      --ids "${virtual_network_ids}" \
      --output none
  else
    echo "No Virtual Network found."
  fi

  # Deleting Network Security Groups, if any.
  network_security_group_ids="$(az network nsg list \
      --output tsv \
      --query "[].id" \
      --resource-group "${parameters[--resource-group-name]}" \
    )"
  if [ -n "${network_security_group_ids}" ]; then
    echo "Deleting Network Security Groups..."
    az network nsg delete \
      --ids "${network_security_group_ids}" \
      --output none
  else
    echo "No Network Security Group Found."
  fi

  # Deleting Public IPs other then Application Gateway Public IP, if any.
  public_ip_ids="$(az network public-ip list \
      --output tsv \
      --query "[?!contains(name,'-AG-')].id" \
      --resource-group "${parameters[--resource-group-name]}" \
    )"
  if [ -n "${public_ip_ids}" ]; then
    echo "Deleting Public IPs..."
    az network public-ip delete \
      --ids "${public_ip_ids}" \
      --output none
  else
    echo "No Public Ip Found."
  fi

  # Deleting the Recovery Service Vault, if any.
  recovery_service_vault_ids="$(az backup vault list \
      --output tsv \
      --query "[].id" \
      --resource-group "${parameters[--resource-group-name]}" \
    )"
  if [ -n "${recovery_service_vault_ids}" ]; then
    echo "Disabling Recovery Service Vault Soft Delete feature..."
    az backup vault backup-properties set \
      --ids "${recovery_service_vault_ids}" \
      --output none \
      --soft-delete-feature-state Disable

    echo "Deleting backup items..."
    recovery_service_vault_names="$(az backup vault list \
        --output tsv \
        --query "[].name" \
        --resource-group "${parameters[--resource-group-name]}" \
      )"
    for recovery_service_vault_name in ${recovery_service_vault_names}; do
      backup_item_ids="$(az backup item list \
          --output tsv \
          --query "[].id" \
          --resource-group "${parameters[--resource-group-name]}" \
          --vault-name "${recovery_service_vault_name}" \
        )"
      az backup protection disable \
        --delete-backup-data true \
        --ids "${backup_item_ids}" \
        --output none \
        --yes
    done

    echo "Deleting Recovery Service Vaults..."
    az backup vault delete \
      --force \
      --ids "${recovery_service_vault_ids}" \
      --output none \
      --yes
  else
    echo "No Recovery Service Vault Found."
  fi

  # Deleting Log Anaytics Workspaces, if any.
  log_analytics_workspace_names="$(az monitor log-analytics workspace list \
      --output tsv \
      --query "[].name" \
      --resource-group "${parameters[--resource-group-name]}" \
    )"
  if [ -n "${log_analytics_workspace_names}" ]; then
    echo "Deleting Log Analytics Workspaces..."
    for log_analytics_workspace_name in ${log_analytics_workspace_names}; do
      az monitor log-analytics workspace delete \
        --force "true" \
        --output none \
        --resource-group "${parameters[--resource-group-name]}" \
        --workspace-name "${log_analytics_workspace_name}" \
        --yes
    done
  else
    echo "No Log Analytics Workspace Found."
  fi
}

main "$@"
