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
  local index
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

  echo "Deleting Virtual Machines, if any..."
  vm_ids="$(az vm list \
      --output tsv \
      --query "[].id" \
      --resource-group "${parameters[--resource-group-name]}" \
    )"
  if [ -z "${vm_ids}" ]; then
    echo "No Virtual Machine Found. Skipping."
  else
    index=0
    for vm_id in ${vm_ids}; do
      ((++index))
      echo "(${index}) Deleting ${vm_id}..."
      az vm delete \
        --ids "${vm_id}" \
        --output none \
        --yes
    done
  fi

  echo "Deleting Disks, if any..."
  disk_ids="$(az disk list \
      --output tsv \
      --query "[].id" \
      --resource-group "${parameters[--resource-group-name]}" \
    )"
  if [ -z "${disk_ids}" ]; then
    echo "No Disk Found. Skipping."
  else
    index=0
    for disk_id in ${disk_ids}; do
      ((++index))
      echo "(${index}) Deleting ${disk_id}..."
      az disk delete \
        --ids "${disk_id}" \
        --output none \
        --yes
    done
  fi

  echo "Deleting Network Interface Cards, if any..."
  network_interface_card_ids="$(az network nic list \
      --output tsv \
      --query "[].id" \
      --resource-group "${parameters[--resource-group-name]}" \
    )"
  if [ -z "${network_interface_card_ids}" ]; then
    echo "No Network Interface Card Found. Skipping."
  else
    index=0
    for network_interface_card_id in ${network_interface_card_ids}; do
      ((++index))
      echo "(${index}) Deleting ${network_interface_card_id}..."
      az network nic delete \
        --ids "${network_interface_card_id}" \
        --output none
    done
  fi

  echo "Deleting Storage Accounts, if any..."
  storage_account_ids="$(az storage account list \
      --output tsv \
      --query "[].id" \
      --resource-group "${parameters[--resource-group-name]}" \
    )"
  if [ -z "${storage_account_ids}" ]; then
    echo "No Storage Account found. Skipping."
  else
    index=0
    for storage_account_id in ${storage_account_ids}; do
      ((++index))
      echo "(${index}) Deleting ${storage_account_id}..."
      az storage account delete \
        --ids "${storage_account_id}" \
        --output none \
        --yes
    done
  fi

  echo "Deleting Postgres Server, if any..."
  postgres_server_ids="$(az postgres flexible-server list \
      --output tsv \
      --query "[].id" \
      --resource-group "${parameters[--resource-group-name]}" \
    )"
  if [ -z "${postgres_server_ids}" ]; then
    echo "No Postgres Server Found. Skipping."
  else
    index=0
    for postgres_server_id in ${postgres_server_ids}; do
      ((++index))
      echo "(${index}) Deleting ${postgres_server_id}..."
      az postgres flexible-server delete \
        --ids "${postgres_server_id}" \
        --output none \
        --yes
    done
  fi

  echo "Deleting Private DNS Zones, if any..."
  private_dns_zone_names="$(az network private-dns zone list \
      --output tsv \
      --query "[].name" \
      --resource-group "${parameters[--resource-group-name]}"
    )"
  if [ -z "${private_dns_zone_names}" ]; then
    echo "No Private DNS Zones Found. Skipping."
  else
    index=0
    for private_dns_zone_name in ${private_dns_zone_names}; do
      ((++index))
      echo "(${index}) Deleting ${private_dns_zone_name}..."
      az network private-dns zone delete \
        --name "${private_dns_zone_name}" \
        --output none \
        --resource-group "${parameters[--resource-group-name]}"
    done
  fi

  echo "Deleting Bastion Service, if any..."
  bastion_names="$(az network bastion list \
      --output tsv \
      --query "[].name" \
      --resource-group "${parameters[--resource-group-name]}" \
    )"
  if [ -z "${bastion_names}" ]; then
    echo "No Bastion Service Found. Skipping."
  else
    index=0
    for bastion_name in ${bastion_names}; do
      ((++index))
      echo "(${index}) Deleting ${bastion_name}..."
      az network bastion delete \
        --name "${bastion_name}" \
        --output none \
        --resource-group "${parameters[--resource-group-name]}"
    done
  fi

  echo "Deleting Application Gateways, if any..."
  application_gateway_ids="$(az network application-gateway list \
      --output tsv \
      --query "[].id" \
      --resource-group "${parameters[--resource-group-name]}" \
    )"
  if [ -z "${application_gateway_ids}" ]; then
    echo "No Application Gateway Found. Skipping."
  else
    index=0
    for application_gateway_id in ${application_gateway_ids}; do
      ((++index))
      echo "(${index}) Deleting ${application_gateway_id}..."
      az network application-gateway delete \
        --ids "${application_gateway_id}" \
        --output none
    done
  fi

  echo "Deleting Virtual Networks, if any..."
  virtual_network_ids="$(az network vnet list \
      --output tsv \
      --query "[].id" \
      --resource-group "${parameters[--resource-group-name]}" \
    )"
  if [ -z "${virtual_network_ids}" ]; then
    echo "No Virtual Network found. Skipping."
  else
    index=0
    for virtual_network_id in ${virtual_network_ids}; do
      ((++index))
      echo "(${index}) Deleting ${virtual_network_id}..."
      az network vnet delete \
        --ids "${virtual_network_id}" \
        --output none
    done
  fi

  echo "Deleting Network Security Groups, if any..."
  network_security_group_ids="$(az network nsg list \
      --output tsv \
      --query "[].id" \
      --resource-group "${parameters[--resource-group-name]}" \
    )"
  if [ -z "${network_security_group_ids}" ]; then
    echo "No Network Security Group Found. Skipping."
  else
    index=0
    for network_security_group_id in ${network_security_group_ids}; do
      ((++index))
      echo "(${index}) Deleting ${network_security_group_id}..."
      az network nsg delete \
        --ids "${network_security_group_id}" \
        --output none
    done
  fi

  echo "Deleting Public IPs other then Application Gateway Public IP, if any..."
  public_ip_ids="$(az network public-ip list \
      --output tsv \
      --query "[?!contains(name,'-AG-')].id" \
      --resource-group "${parameters[--resource-group-name]}" \
    )"
  if [ -z "${public_ip_ids}" ]; then
    echo "No Public Ip Found. Skipping."
  else
    index=0
    for public_ip_id in ${public_ip_ids}; do
      ((++index))
      echo "(${index}) Deleting ${public_ip_id}..."
      az network public-ip delete \
        --ids "${public_ip_id}" \
        --output none
    done
  fi

  echo "Deleting the Recovery Service Vault, if any..."
  recovery_service_vault_ids="$(az backup vault list \
      --output tsv \
      --query "[].id" \
      --resource-group "${parameters[--resource-group-name]}" \
    )"
  if [ -z "${recovery_service_vault_ids}" ]; then
    echo "No Recovery Service Vault Found. Skipping."
  else
    index=0
    for recovery_service_vault_id in ${recovery_service_vault_ids}; do
      ((++index))
      echo "(${index}) Processing ${recovery_service_vault_id}..."

      echo "(${index}) Disabling Soft Delete feature..."
      az backup vault backup-properties set \
        --ids "${recovery_service_vault_id}" \
        --output none \
        --soft-delete-feature-state Disable

      echo "(${index}) Retrieving Backup Items..."
      recovery_service_vault_name="$(az backup vault list \
          --output tsv \
          --query "[?id == '${recovery_service_vault_id}'].name" \
          --resource-group "${parameters[--resource-group-name]}" \
        )"
      backup_item_ids="$(az backup item list \
          --output tsv \
          --query "[].id" \
          --resource-group "${parameters[--resource-group-name]}" \
          --vault-name "${recovery_service_vault_name}" \
        )"

      echo "(${index}) Disabling Backup Items' protection..."
      az backup protection disable \
        --delete-backup-data true \
        --ids "${backup_item_ids}" \
        --output none \
        --yes

      echo "(${index}) Deleting Recovery Service Vault..."
      az backup vault delete \
        --force \
        --ids "${recovery_service_vault_id}" \
        --output none \
        --yes
    done
  fi

  echo "Deleting Log Analytics Workspaces, if any..."
  log_analytics_workspace_names="$(az monitor log-analytics workspace list \
      --output tsv \
      --query "[].name" \
      --resource-group "${parameters[--resource-group-name]}" \
    )"
  if [ -z "${log_analytics_workspace_names}" ]; then
    echo "No Log Analytics Workspace Found. Skipping."
  else
    index=0
    for log_analytics_workspace_name in ${log_analytics_workspace_names}; do
      ((++index))
      echo "(${index}) Deleting ${log_analytics_workspace_name}..."
      az monitor log-analytics workspace delete \
        --force "true" \
        --output none \
        --resource-group "${parameters[--resource-group-name]}" \
        --workspace-name "${log_analytics_workspace_name}" \
        --yes
    done
  fi
}

main "$@"
