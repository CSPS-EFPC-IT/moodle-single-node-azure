#!/bin/bash
# Implements a library of commonly used functions, namely:
# - echo_action
# - echo_error
# - echo_info
# - echo_title
# - parse_parameters
# - set_trap
# - unset_trap

# Constants
readonly DATE_FORMAT='%Y-%m-%d %H:%M:%S (%Z)'

# Functions
function echo_action() {
  echo ""
  echo "$(date +"$DATE_FORMAT") | ACTION - $1"
}

function echo_error() {
  echo "$(date +"$DATE_FORMAT") | ERROR  - $1" >&2
}

function echo_info() {
  echo "$(date +"$DATE_FORMAT") | INFO   - $1"
}

function echo_title() {
  echo ""
  echo "###############################################################################"
  echo "$1"
  echo "###############################################################################"
}

# Assumptions:
# - A global associative array named "parameters" exists.
function parse_parameters() {
  local readonly PARAMETER_KEY_PREFIX="--"
  local readonly PARAMETER_KEY_REGEX_PATTERN="^${PARAMETER_KEY_PREFIX}.*$"

  local missing_parameter_flag=false
  local sorted_parameter_keys=$(echo ${!parameters[@]} | tr " " "\n" | sort | tr "\n" " ");
  local unexpected_parameter_flag=false
  local usage="USAGE: $(basename $0)"

  echo_action "Mapping input parameter values and checking for unexpected parameters..."
  while [[ ${#@} -gt 0 ]];
  do
    key=$1
    value=$2

    # Test if the parameter key start with the PARAMETERS_PREFIX and if the parameter
    # key without the PARAMETERS_PREFIX is in the expected parameter list.
    if [[ ${key} =~ $PARAMETER_KEY_REGEX_PATTERN && ${parameters[${key:${#PARAMETER_KEY_PREFIX}}]+_} ]]; then
      parameters[${key:${#PARAMETER_KEY_PREFIX}}]="${value}"
    else
      echo_error "Unexpected parameter: ${key}"
      unexpected_parameter_flag=true
    fi

    # Move to the next key/value pair or up to the end of the parameter list.
    shift $(( 2 < ${#@} ? 2 : ${#@} ))
  done
  echo_info "Done."

  echo_action "Checking for missing parameters..."
  for parameter_key in ${sorted_parameter_keys}; do
    if [[ -z ${parameters[${parameter_key}]} ]]; then
      echo_error "Missing parameter: ${parameter_key}."
      missing_parameter_flag=true
    fi
  done
  echo_info "Done."

  # Abort if missing or extra parameters.
  if [[ ${unexpected_parameter_flag} == "true" || ${missing_parameter_flag} == "true" ]]; then
    echo_error "Execution aborted due to missing or extra parameters."
    for parameter_key in ${sorted_parameter_keys}; do
      usage="${usage} -${parameter_key} \$${parameter_key}"
    done
    echo_error "${usage}";
    exit 1;
  fi

  echo_action 'Printing input parameter values fro debugging purposes...'
  for parameter_key in ${sorted_parameter_keys}; do
    echo_info "${parameter_key} = \"${parameters[${parameter_key}]}\""
  done
  echo_info "Done."
}

function set_trap() {
  # Exit when any command fails
  set -e
  # Keep track of the last executed command
  trap 'last_command=${current_command}; current_command=$BASH_COMMAND' DEBUG
  # Echo an error message before exiting
  trap 'echo "\"${last_command}\" command failed with exit code $?."' EXIT
}

function unset_trap() {
  # Remove all trap
  trap - EXIT
}
