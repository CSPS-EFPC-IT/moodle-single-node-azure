#!/bin/bash
# Implements useful logging functions.

readonly DATE_FORMAT='%Y-%m-%d %H:%M:%S (%Z)'

function echo_title {
  echo ""
  echo "###############################################################################"
  echo "$1"
  echo "###############################################################################"
}

function echo_action {
  echo ""
  echo "$(date +"$DATE_FORMAT") | ACTION - $1"
}

function echo_info {
  echo "$(date +"$DATE_FORMAT") | INFO   - $1"
}

function echo_error {
  echo "$(date +"$DATE_FORMAT") | ERROR  - $1" >&2
}