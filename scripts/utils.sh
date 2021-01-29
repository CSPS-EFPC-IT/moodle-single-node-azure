#!/bin/bash
#
# Implements a package of utility functions.
# Style Guide: https://google.github.io/styleguide/shellguide.html

# Constants
readonly DATE_FORMAT='%Y-%m-%d %H:%M:%S (%Z)'

# Function's comment template
#######################################
# [Description of the function.]
# Globals:
#   [List of global variables used and modified, if any.]
# Arguments:
#   [Arguments taken, if any.]
# Outputs:
#   [Output to STDOUT or STDERR, if any.]
# Returns:
#   [Returned values other than the default exit status of the last command run.]
#######################################

#######################################
# Add new commented entry in server hosts file.
# Arguments:
#   1) IP address to add
#   2) Corresponding Fully Qualified Domain Name to add
#   3) Corresponding entry comment to add
# Outputs:
#   Writes log to STDOUT.
#######################################
function utils::add_hosts_file_entry() {
  local ip="$1"
  local fqdn="$2"
  local comment="$3"

  readonly HOSTS_FILE_PATH="/etc/hosts"

  echo_action "Adding entry for ${fqdn} in ${HOSTS_FILE_PATH}..."
  if ! grep -q "${fqdn}" "${HOSTS_FILE_PATH}"; then
    printf "# ${comment}\n${ip} ${fqdn}\n" >> "${HOSTS_FILE_PATH}"
    echo_info "Done."
  else
    echo_info "Skipped: ${HOSTS_FILE_PATH} already contains entry for ${fqdn}."
  fi
}

#######################################
# Echo a text string using the ACTION format.
# Globals:
#   DATE_FORMAT
# Arguments:
#   Message to echo
# Outputs:
#   Writes message to echo to STDOUT.
#######################################
function utils::echo_action() {
  echo ""
  echo "$(date +"$DATE_FORMAT") | ACTION - $1"
}

#######################################
# Echo a text string using the ERROR format.
# Globals:
#   DATE_FORMAT
# Arguments:
#   Message to echo
# Outputs:
#   Writes message to echo to STDERR.
#######################################
function utils::echo_error() {
  echo "$(date +"$DATE_FORMAT") | ERROR  - $1" >&2
}

#######################################
# Echo a text string using the INFO format.
# Globals:
#   DATE_FORMAT
# Arguments:
#   Message to echo
# Outputs:
#   Writes message to echo to STDOUT.
#######################################
function utils::echo_info() {
  echo "$(date +"$DATE_FORMAT") | INFO   - $1"
}

#######################################
# Echo a text string using the TITLE format.
# Arguments:
#   Message to echo
# Outputs:
#   Writes message to echo to STDOUT.
#######################################
function utils::echo_title() {
  echo ""
  echo "###############################################################################"
  echo "$1"
  echo "###############################################################################"
}

#######################################
# Harden Apache2 Webserver settings.
# Arguments:
#   Apache2 security configuration file to update, a file path.
# Outputs:
#   Writes normal log messages to STDOUT.
#   Writes error messages to STDERR.
#######################################
function utils::harden_apache2() {
  local config_file_path="$1"

  update_apache2_config_file "ServerTokens" "Prod" "${config_file_path}"
  update_apache2_config_file "ServerSignature" "Off" "${config_file_path}"
}

#######################################
# Mount a data disk identified by its size to a mount point.
# Since that is no way to predict the device name of a data disk, we use the
# device size as to identify the data disk. This means that is it impossible
# to use this function utils::to mount a data disk that has the same size as another
# device attached to the server.
# The data disk is formated if no file system exists.
# Globals:
# Arguments:
#   1) size of the disk to mount, a string as returned by the
#      "lsblk --output name,size" command.
#   2) mount_point_path, a path
# Outputs:
#   Writes normal log messages to STDOUT.
#   Writes error messages to STDERR.
#######################################
function utils::mount_data_disk_by_size() {
  local data_disk_size="$1"
  local data_disk_mount_point_path="$2"

  readonly DEFAULT_FILE_SYSTEM_TYPE="ext4"
  readonly FSTAB_FILE_PATH="/etc/fstab"
  readonly TIMEOUT=60

  local data_disk_block_path
  local data_disk_file_system_type
  local data_disk_file_system_uuid
  local elapsed_time

  echo_action 'Retrieving data disk block path using data disk size as index...'
  data_disk_block_path="/dev/$(lsblk --noheadings --output name,size | awk "{if (\$2 == \"${data_disk_size}\") print \$1}")"
  echo_info "Data disk block path found: ${data_disk_block_path}"
  echo_info "Done."

  echo_action 'Creating file system on data disk block if none exists...'
  data_disk_file_system_type="$(lsblk --noheadings --output fstype ${data_disk_block_path})"
  if [ -z "${data_disk_file_system_type}" ]; then
    echo_info "No file system detected on ${data_disk_block_path}."
    data_disk_file_system_type="${DEFAULT_FILE_SYSTEM_TYPE}"
    echo_action "Creating file system of type ${data_disk_file_system_type} on ${data_disk_block_path}..."
    mkfs.${data_disk_file_system_type} ${data_disk_block_path}
    echo_info "Done."
  else
    echo_info "Skipped: File system ${data_disk_file_system_type} already exist on ${data_disk_block_path}."
  fi

  echo_action 'Retrieving data disk file system UUID...'
  # Bug Fix:  Experience demonstrated that the UUID of the new file system is not immediately
  #           available through lsblk, thus we wait and loop for up to 60 seconds to get it.
  elapsed_time=0
  data_disk_file_system_uuid=""
  while [[ -z "${data_disk_file_system_uuid}" && "${elapsed_time}" -lt "${TIMEOUT}" ]]; do
    echo_info "Waiting for 1 second..."
    sleep 1
    data_disk_file_system_uuid="$(lsblk --noheadings --output UUID "${data_disk_block_path}")"
    ((elapsed_time+=1))
  done
  if [[ -z "${data_disk_file_system_uuid}" ]]; then
    echo_error "Could not retrieve the data disk file system UUID within ${TIMEOUT} seconds. Aborting."
    exit 1
  else
    echo_info "Data disk file system UUID: ${data_disk_file_system_uuid}"
  fi
  echo_info "Done."

  echo_action "Creating data disk mount point at ${data_disk_mount_point_path}..."
  mkdir -p "${data_disk_mount_point_path}"
  echo_info "Done."

  echo_action "Updating ${FSTAB_FILE_PATH} file to automount the data disk using its UUID..."
  if grep -q "${data_disk_file_system_uuid}" "${FSTAB_FILE_PATH}"; then
    echo_info "Skipped: already set up."
  else
    printf "UUID=${data_disk_file_system_uuid}\t${data_disk_mount_point_path}\t${data_disk_file_system_type}\tdefaults,nofail\t0\t2\n" >> "${FSTAB_FILE_PATH}"
    echo_info "Done."
  fi

  echo_action 'Mounting all drives...'
  mount -a
  echo_info "Done."
}

#######################################
# Parse and set script parameters into associative array.
# Globals:
#   parameters: An associative array for script parameters.
# Arguments:
#   The whole script command line ($@) where:
#     parameter keys are prefix with "--"
#     parameter key and value are separated by with space(s).
#   Ex.: myscript --parm1 value1 --parm2 value2
# Outputs:
#   Writes normal log messages to STDOUT.
#   Writes error messages to STDERR.
# Returns:
#   0 on success
#   1 on failure
#######################################
function utils::parse_parameters() {
  local readonly KEY_PREFIX="--"
  local readonly KEY_REGEX_PATTERN="^${KEY_PREFIX}.*$"

  local key
  local missing_parameter_flag
  local sorted_keys
  local unexpected_parameter_flag
  local usage
  local value

  echo_action "Mapping input parameter values and checking for unexpected parameters..."
  unexpected_parameter_flag=false
  while [[ ${#@} -gt 0 ]]; do
    key=$1
    value=$2

    # Test if the parameter key start with the KEY_PREFIX and if the parameter
    # key without the PARAMETERS_PREFIX is in the expected parameter list.
    if [[ ${key} =~ $KEY_REGEX_PATTERN && ${parameters[${key:${#KEY_PREFIX}}]+_} ]]; then
      parameters[${key:${#KEY_PREFIX}}]="${value}"
    else
      echo_error "Unexpected parameter: ${key}"
      unexpected_parameter_flag=true
    fi

    # Move to the next key/value pair or up to the end of the parameter list.
    shift $(( 2 < ${#@} ? 2 : ${#@} ))
  done
  echo_info "Done."

  echo_action "Checking for missing parameters..."
  sorted_keys=$(echo ${!parameters[@]} | tr " " "\n" | sort | tr "\n" " ");
  missing_parameter_flag=false
  for key in ${sorted_keys}; do
    if [[ -z ${parameters[${key}]} ]]; then
      echo_error "Missing parameter: ${key}."
      missing_parameter_flag=true
    fi
  done
  echo_info "Done."

  # Abort if missing or extra parameters.
  usage="USAGE: $(basename $0)"
  if [[ ${unexpected_parameter_flag} == "true" || ${missing_parameter_flag} == "true" ]]; then
    echo_error "Execution aborted due to missing or extra parameters."
    for key in ${sorted_keys}; do
      usage="${usage} -${key} \$${key}"
    done
    echo_error "${usage}";
    exit 1;
  fi

  echo_action 'Printing input parameter values for debugging purposes...'
  for key in ${sorted_keys}; do
    echo_info "${key} = \"${parameters[${key}]}\""
  done
  echo_info "Done."

  echo_action 'Locking down parameters array...'
  readonly parameters
  echo_info "Done."
}

#######################################
# Set EXIT trap to echo last command and its exit code.
# Globals:
#   $BASH_COMMAND
#   last_command
#   current_command
# Outputs:
#   Writes last command and exit code to STDOUT.
#######################################
function utils::set_exit_trap() {
  # Keep track of the last executed command
  trap 'last_command=${current_command}; current_command=${BASH_COMMAND}' DEBUG
  # Echo an error message before exiting
  trap 'echo "\"${last_command}\" exited with code $?."' EXIT
}

#######################################
# Update the value of existing and enabled parameter in an Apache2 config file.
# Arguments:
#   1) Parameter to set, text string.
#   2) Value to set, text string.
#   3) Apache2 config file to update, file path.
# Outputs:
#   Writes normal log messages to STDOUT.
#   Writes error messages to STDERR.
#######################################
function utils::update_apache2_config_file() {
  local parameter="$1"
  local value="$2"
  local config_file_path="$3"

  echo_action "Setting \"${parameter}\" to \"${value}\" in ${config_file_path}..."

  # Check if one and only one line match the search criteria.
  case $(grep "^[[:blank:]]*${parameter}[[:blank:]].*$" "${config_file_path}" | wc -l) in
    0)
      echo_error "No line matched the search criteria. Aborting."
      exit 1
      ;;
    1)
      echo_info "One line matched the search criteria."
      ;;
    *)
      echo_error "More than one line matched the search criteria. Aborting."
      exit 1
      ;;
  esac

  # Perform substitution while maintaining code indentation.
  sed -i -E "s|^([[:blank:]]*)${parameter}[[:blank:]].*$|\1${parameter} ${value}|g" "${config_file_path}"

  echo_info "Done."
}

#######################################
# Update the value of existing and already enabled parameter in a PHP config file.
# Arguments:
#   1) Parameter to set, text string.
#   2) Value to set, text string.
#   3) PHP file to update, file path
# Outputs:
#   Writes log messages to STDOUT.
#   Writes error messages to STDERR.
#######################################
function utils::update_php_config_file() {
  local parameter="$1"
  local value="$2"
  local config_file_path="$3"

  local regex

  echo_action "Setting \"${parameter}\" to \"${value}\" in ${config_file_path}..."

  # Check if one and only one line match the search criteria.
  regex="^${parameter}[[:blank:]]*=.*$"
  case $(grep "${regex}" "${config_file_path}" | wc -l) in
    0)
      echo_error "No line matched the search criteria. Aborting."
      exit 1
      ;;
    1)
      echo_info "One line matched the search criteria."
      ;;
    *)
      echo_error "More than one line matched the search criteria. Aborting."
      exit 1
      ;;
  esac

  # Perform substitution.
  sed -i -E "s|${regex}|${parameter} = ${value}|g" "${config_file_path}"

  echo_info "Done."
}

#######################################
# Counter part of set_exit_trap.
#######################################
function utils::unset_exit_trap() {
  trap - DEBUG
  trap - EXIT
}
