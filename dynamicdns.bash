#!/bin/bash

# This script updates a DNS A record hosted by Dreamhost to your current IP
# address via the Dreamhost API.
#
# =============================================================================
#
# Copyright (c) 2013, Paul Clement
# All rights reserved.
#
# Additional changes and updates as noted via https://github.com/jgabello/dreamhost-dynamic-dns Copyright (c) 2014, Contributing Author
# See LICENSE for more details.

CONFIG_DIR="${XDG_CONFIG_HOME:=$HOME/.config}/dreamhost-dynamicdns" && mkdir -p "$CONFIG_DIR" && chmod 0700 "$CONFIG_DIR"
CONFIG_FILE="$CONFIG_DIR/config.sh"
#Default to IPV4
IP_TYPE="A"
IP4_ONLY="false"

if [ -f "$HOME/.config/dynamicdns" ]; then
  echo "Migrating to new config location."
  mv "$HOME/.config/dynamicdns" "$CONFIG_FILE"
fi

function usage {
  echo 'usage:  ' "$(basename "$0")" '[-Sdvlh46][-k API Key] [-r Record] [-i New IP Address] [-L Logging (true/false)]'
}

function help {
  usage
  cat << EOF
  The options are as follows:

    -S Save any options provided via the command line to the configuration file.

    -d Save any options provided via the command line to the configuration file and do not update DNS.

    -h this help text

    -4 IPv4 only (Otherwise will try IPv4 first and then fall back to IPv6)

    -6 IPv6 only. (Only use IPv6)

    -v Enable verbose mode.

    -l Enable list-only mode, showing only current value returned by the Dreamhost API.

    -k API Key
    Dreamhost API Key with dns-list_records, dns-remove_record, and dns-add_record permissions.

    -r Record
    The DNS Record to be updated.

    -i IP Address
    Specify the IPv4 Address to update the Record to.
    If no address is specified, the utility will use dig to
    obtain the current public IPv4 Address of your computer.

    -L (true/false)
    Enables system logging via the logger command. The configuration file sets logging to true by default.

EOF
}

# Function to validate IPv4
function is_ipv4 {
    [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

# Function to validate IPv6
function is_ipv6 {
    [[ $1 =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$ ]]
}

# Function to get IP from a given service and regex pattern
function get_ip {
  local this_IPV=$1
  local this_IP_TYPE
  if [[ "$this_IPV" == 4 ]]; then
    this_IP_TYPE="A"
  else
    this_IP_TYPE="AAAA"
  fi
  if [ "$VERBOSE" = "true" ]; then
    echo "No IP Address provided, obtaining public IP" >&2
  fi
  # Try multiple resolvers (in case they don't respond)
  RESOLVERS="
    o-o.myaddr.l.google.com:ns1.google.com:TXT
    myip.opendns.com:resolver1.opendns.com:$this_IP_TYPE
    whoami.akamai.net:ns1-1.akamaitech.net:$this_IP_TYPE
    o-o.myaddr.l.google.com:ns2.google.com:TXT
    myip.opendns.com:resolver2.opendns.com:$this_IP_TYPE
    o-o.myaddr.l.google.com:ns3.google.com:TXT
    myip.opendns.com:resolver3.opendns.com:$this_IP_TYPE
    o-o.myaddr.l.google.com:ns4.google.com:TXT
    myip.opendns.com:resolver4.opendns.com:$this_IP_TYPE
  "

  for ENTRY in $RESOLVERS; do
    IFS=':' read -r OWN_HOSTNAME RESOLVER DNS_RECORD <<< "$ENTRY"
    if [ "$VERBOSE" = "true" ]; then
      echo "Running: dig -$this_IPV +short" "$DNS_RECORD" "$OWN_HOSTNAME" @"$RESOLVER" >&2
    fi
    if IP=$(dig -"$this_IPV" +short "$DNS_RECORD" "$OWN_HOSTNAME" @"$RESOLVER"); then
      break
    fi
    logStatus "notice" "Failed to obtain current IP$this_IPV address using $RESOLVER"
  done

  IP=${IP//\"/}

  echo "$IP"
}


function createConfigurationFile {
  umask 077
  cat << EOF > "$CONFIG_FILE"
# Dreamhost Dynamic DNS Updater Configuration file.  This file
# allows you to set the basic parameters to update Dreamhost
# dynamic dns without command line options.
# There are three basic parameters:
#
# KEY
# This parameter is your Dreamhost API Key.  The parameter should
# be specified as a STRING.  Your API KEY must be given the the
# following permissions in the Dreamhost webpanel:
# - dns-list_records
# - dns-remove_record
# - dns-add_record

KEY=

# RECORD
# This parameter specifies which DNS A record you wish to update
# with this script.

RECORD=

# LOGGING
# Logging enables script output to the system log in OSX or Linux
# This parameter accepts a BOOLEAN.  By default this parameter is
# set to "true".
#

LOGGING=true
EOF

  return 0
}

function logStatus {
  local LEVEL=$1
  local MESSAGE=$2
  if [ "$LOGGING" = "true" ]; then
    if [ "$LEVEL" = "error" ]; then
      logger -p syslog.err -t "$(basename "$0")" "$MESSAGE"
    elif [ "$LEVEL" = "notice" ]; then
      logger -p syslog.notice -t "$(basename "$0")" "$MESSAGE"
    elif [ "$LEVEL" = "alert" ]; then
      logger -p syslog.alert -t "$(basename "$0")" "$MESSAGE"
    fi
  fi
  if [ $VERBOSE = "true" ]; then
    echo "$(basename "$0")" "$MESSAGE"
  fi
  return 0
}

function saveConfiguration {
  if [ -n "$1" ]; then
    sed -i -e "s/^KEY=.*$/KEY=$1/" "$CONFIG_FILE"
    if [ $VERBOSE = "true" ]; then
      echo "Saving KEY to configuration file"
    fi
  fi

  if [ -n "$2" ]; then
    sed -i -e "s/^RECORD=.*$/RECORD=$2/" "$CONFIG_FILE"
    if [ $VERBOSE = "true" ]; then
      echo "Saving RECORD to configuration file"
    fi

  fi
  if [ -n "$3" ]; then
    sed -i -e "s/^LOGGING=.*$/LOGGING=$3/" "$CONFIG_FILE"
    if [ $VERBOSE = "true" ]; then
      echo "Saving LOGGING to configuration file"
    fi
  fi
  return 0
}

VERBOSE="false"
LISTONLY="false"
#Get Command Line Options
while getopts "L:i:k:r:Sdvhl46" OPTS
do
  case $OPTS in
    L)
    if [ "$OPTARG" != "true" ] && [ "$OPTARG" != "false" ]; then
      echo "$(basename "$0")" " Invalid Parameters -- L"
      logStatus "error" "Invalid Parameters -- L"
      usage
      exit 1
    fi

    OPTLOGGING=$OPTARG
    ;;

    4)
    IP_TYPE="A"
    IP4_ONLY="true"
    ;;

    6)
    IP_TYPE="AAAA"
    ;;

    h)
    help
    exit 0
    ;;

    v)
    VERBOSE="true"
    ;;

    k)
    OPTKEY=$OPTARG
    ;;

    l)
    LISTONLY="true"
    ;;

    r)
    OPTRECORD=$OPTARG
    ;;

    i)
    if [[ $OPTARG =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]];
    then
      OPTIP=$OPTARG
    else
      echo "$(basename "$0")" " Invalid Parameters -- i"
      logStatus "error" "Invalid Parameters -- i"
      usage
      exit 1
    fi
    ;;

    S)
    SAVE="true"
    ;;

    d)
    SAVEONLY="true"
    ;;

    ?)
    usage
    exit 1
    ;;
  esac
done

#Check for Configuration File

if [ ! -f "$CONFIG_FILE" ]; then
  logStatus "notice" "Configuration File Not Found. Creating new configuration file."
  createConfigurationFile
fi

# Load Configuration File
# shellcheck disable=SC1090
source "$CONFIG_FILE"

# check for dependencies, if wget not available, test for curl, set variable to be used to test this later
if command -v wget >/dev/null 2>&1; then
  POSTPROCESS="wget"

elif command -v curl >/dev/null 2>&1; then
  POSTPROCESS="curl"

else
  echo "$(basename "$0")" "ERROR: Missing dependency -- wget or curl"
  logStatus "error" "Missing Dependency -- wget or curl"
  exit 1
fi
if [ $VERBOSE = "true" ]; then
  echo "Post process set to: $POSTPROCESS"
fi

OS_PREREQS=(uuidgen grep awk sed dig)

NOT_FOUND=()
for cmd in "${OS_PREREQS[@]}"; do
  if [ ! "$(which "$cmd")" ]; then
    NOT_FOUND+=("$cmd")
  fi
done

if [ ${#NOT_FOUND[@]} -gt 0 ]; then
  echo "$(basename "$0")" "ERROR: Missing Depenencies: ${NOT_FOUND[*]}"
  logStatus "error" "Missing Dependencies: ${NOT_FOUND[*]}"
  exit 1
fi

if [ -z "$OPTKEY" ]; then
  if [ -z "$KEY" ]; then
    echo "$(basename "$0")" ": missing parameter -- KEY"
    logStatus "error" "Missing Parameter -- KEY"
    usage
    exit 1
  fi
else KEY="$OPTKEY"
fi

if [ -z "$OPTRECORD" ]; then
  if [ -z "$RECORD" ]; then
    echo "$(basename "$0")" ": missing parameter -- RECORD"
    logStatus "error" "Missing Parameter -- RECORD"
    usage
   exit 1
  fi
else RECORD="$OPTRECORD"
fi

if [ $VERBOSE = "true" ]; then
  echo "Using API Key: $KEY"
  echo "Updating RECORD: $RECORD"
fi

if [ "$SAVE" == "true" ] || [ "$SAVEONLY" == "true" ]; then
  saveConfiguration "$OPTKEY" "$OPTRECORD" "$OPTLOGGING"
fi

if [ "$SAVEONLY" == "true" ]; then
  if [ $VERBOSE = "true" ]; then
    echo "Saving Configuration File and Exiting"
  fi
  exit 0
fi

if [ -z "$OPTIP" ]; then
  #Test for IP4 first unless the -6 flag is set (IPV6 only)
  if [[ $IP_TYPE == "A" ]]; then
    IP=$(get_ip 4)
    if ! is_ipv4 "$IP"; then
      #fallback to IP6? 
      if [[ "$IP4_ONLY" == "true" ]]; then
        logStatus "error" "Failed to obtain current IPv4 address. No fallback to IPv6"
        exit 3
      else
        echo "Attempting IPv6 as IPv4 failed" >&2
        IP_TYPE="AAAA"
        IP=$(get_ip 6)
        if ! is_ipv6 "$IP"; then
          logStatus "error" "Failed to obtain current IPv4 OR IPv6 address"
          exit 3
        fi
      fi
    fi
  else
    IP=$(get_ip 6)
    if ! is_ipv6 "$IP"; then
      logStatus "error" "Failed to obtain current IPv6 address"
      exit 3
    fi
  fi
  if [ $VERBOSE = "true" ]; then
    echo "Found current public IP: $IP" >&2
  fi
else
  IP="$OPTIP"
fi

function findCurrentRecord {
  local cleaned_record=$1
  local list_resp=$2
  local this_ip_type=$3
  local this_current_record
  if [[ $this_ip_type == "A" ]]; then
    this_current_record=$(echo "$list_resp" | grep -E -o "\s$cleaned_record\s+$this_ip_type\s+[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}")
  else
    this_current_record=$(echo "$list_resp" | grep "\s$cleaned_record\s$this_ip_type\n")
  fi
  #Return the current record
  printf '%s\n' "$this_current_record"
}

function submitApiRequest {
  local KEY=$1
  local CMD=$2
  local ARGS=$3

  if [ $VERBOSE = "true" ]; then
    #Only print to stderr since stdout here is parsed by calling functions.
    printf 'In submitApiRequest: CMD=%s\n' "$CMD" >&2
  fi
  # Send request
  local RESPONSE
  if [ $POSTPROCESS = "wget" ]; then
    if [ $VERBOSE = "true" ]; then
      #Only print to stderr since stdout here is parsed by calling functions.
      printf 'In submitApiRequest: wget -O- -q https://api.dreamhost.com --post-data "key=%s&unique_id=%s&cmd=%s&%s\n' "$KEY" "$(uuidgen)" "$CMD" "$ARGS" >&2
    fi
    RESPONSE=$(wget -O- -q https://api.dreamhost.com/ \
      --post-data "key=$KEY&unique_id=$(uuidgen)&cmd=$CMD&$ARGS" )
  elif [ $POSTPROCESS = "curl" ]; then
    RESPONSE=$(curl -s --data "key=$KEY&unique_id=$(uuidgen)&cmd=$CMD&$ARGS" https://api.dreamhost.com/)
  else
    logStatus "error" "Missing Dependency -- wget or curl"
    exit 1
  fi
  local RC=$?

  # Output Response
  printf '%s\n' "$RESPONSE"

  if [ $RC -ne 0 ]; then
    logStatus "notice" "API Request Failed"
    return $?
  fi

  # If "success" is not the response, then the request failed. Return the following
  echo "$RESPONSE" | grep -q "^success$"
}

function listRecord {
  local KEY=$1
  local RECORD=$2

  # See whether there is already a record for this domain
  # Note: If in double quotes don't escape ampersandi (e.g. "a=b&", if out of quotes do (e.g. a=b\&)

  local LIST_RESP
  if ! LIST_RESP=$(submitApiRequest "$KEY" dns-list_records type=$IP_TYPE\&editable=1); then
    logStatus "notice" "Error Listing Records: $LIST_RESP"
    return 1
  fi

  local CLEANED_RECORD
  CLEANED_RECORD=$(echo "$RECORD" | sed "s/[*]/[*]/g ; s/[.]/[.]/g ")

  local CURRENT_RECORD
  CURRENT_RECORD=$(findCurrentRecord "$CLEANED_RECORD" "$LIST_RESP" "$IP_TYPE")
  if [ $VERBOSE = "true" ]; then
    #print to stderr
    printf 'Current Record: %s\n' "$CURRENT_RECORD" >&2
  fi
  if [[ "$CURRENT_RECORD" == "" ]]; then
    logStatus "error" "Record '$CLEANED_RECORD' not found"
    return 0
  fi

  local OLD_VALUE
  OLD_VALUE=$(echo "$CURRENT_RECORD" | awk '{print $5 }')

  echo "Found current record: $OLD_VALUE"
  return 0
}

function deleteRecord {
  local KEY=$1
  local RECORD=$2
  local NEW_VALUE=$3
  if [ $VERBOSE = "true" ]; then
    echo "In deleteRecord: RECORD=$RECORD"
    echo "In deleteRecord: NEW_VALUE=$NEW_VALUE"
  fi

  # See whether there is already a record for this domain

  local LIST_RESP
  if ! LIST_RESP=$(submitApiRequest "$KEY" dns-list_records type=$IP_TYPE\&editable=1); then
    logStatus "notice" "Error Listing Records: $LIST_RESP"
    return 1
  fi

  local CLEANED_RECORD
  CLEANED_RECORD=$(echo "$RECORD" | sed "s/[*]/[*]/g ; s/[.]/[.]/g ")
  if [ $VERBOSE = "true" ]; then
    #print to stderr
    printf 'Cleaned Record: %s\n' "$CLEANED_RECORD" >&2
  fi

  local CURRENT_RECORD
  CURRENT_RECORD=$(findCurrentRecord "$CLEANED_RECORD" "$LIST_RESP" "$IP_TYPE")
  if [ $VERBOSE = "true" ]; then
    #print to stderr
    printf 'Current Record: %s\n' "$CURRENT_RECORD" >&2
  fi
  if [[ "$CURRENT_RECORD" == "" ]]; then
    logStatus "error" "Record not found"
    return 0
  fi
  if [ $VERBOSE = "true" ]; then
    #print to stderr
    printf 'Current Record: %s\n' "$CURRENT_RECORD" >&2
  fi

  local OLD_VALUE
  OLD_VALUE=$(echo "$CURRENT_RECORD" | awk '{print $3 }')

  if [ "$OLD_VALUE" == "$NEW_VALUE" ]; then
    # The current record is up to date, so we don't need to do anything
    return 255
  fi

  # We need to remove the existing record to continue

  if [ $VERBOSE = "true" ]; then
    #Only print to stderr since this function's stdout value is used.
    printf 'About to delete Old Value: %s\n' "$OLD_VALUE" >&2
  fi
  if ! submitApiRequest "$KEY" dns-remove_record "record=$RECORD&type=$IP_TYPE&value=$OLD_VALUE"; then
    logStatus "error" "Unable to Remove Existing Record"
    printf 'Error: Unable to Remove Old Value: %s\n' "$OLD_VALUE" >&2
    return 2
  else
    return 0
  fi
}

function addRecord {
  local KEY=$1
  local RECORD=$2
  local IP=$3

  #the return value from submitApiRequest is the return value here
  submitApiRequest "$KEY" \
                   dns-add_record \
                   "record=$RECORD&type=$IP_TYPE&value=$IP"
}

# -------------------------------
# Main execution
if [ "$LISTONLY" == "true" ]; then

  # We're just getting the current record

  if ! listRecord "$KEY" "$RECORD"; then
    # Something is wrong
    logStatus "error" "ERROR $?"
    exit $?
  fi

else

  # We're updating the record

  # Delete any existing record for this domain
  deleteRecord "$KEY" "$RECORD" "$IP"
  DELETE_STATUS=$?

  if [ $DELETE_STATUS -eq 255 ]; then
    logStatus "notice" "Record up to date"
    exit 0
  fi

  if [ $DELETE_STATUS -ne 0 ]; then
    # Something is wrong
    logStatus "error" "ERROR $DELETE_STATUS"
    exit $DELETE_STATUS
  fi

  # Add the new record

  if ! addRecord "$KEY" "$RECORD" "$IP"; then
    logStatus "alert" "Failed to add new record"
    # In this case, if we have deleted the record, then you will no longer
    # have a DNS record for this domain.
    exit 4
  else
    logStatus "notice" "Record updated succesfully"
  fi

fi

# Woohoo! We're exiting cleanly
exit 0
