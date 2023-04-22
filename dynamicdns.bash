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

CONFIG="$HOME/.config/dynamicdns"

function usage {
  echo 'usage:  ' `basename $0` '[-Sdv][-k API Key] [-r Record] [-i New IP Address] [-L Logging (true/false)]'
}

function createConfigurationFile {

  if [ ! -d $HOME/.config ]; then
    echo "$HOME/.config/ does not exist, creating directory."
    mkdir $HOME/.config
  fi

  umask 077
echo -n '# Dreamhost Dynamic DNS Updater Configuration file.  This file
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
' > "$CONFIG"

return 0
}

function logStatus {
  local LEVEL=$1
  local MESSAGE=$2
  if [ "$LOGGING" = "true" ]; then
    if [ $LEVEL = "error" ]; then
      logger -p syslog.err -t `basename $0` "$MESSAGE"
    elif [ $LEVEL = "notice" ]; then
      logger -p syslog.notice -t `basename $0` "$MESSAGE"
    elif [ $LEVEL = "alert" ]; then
      logger -p syslog.alert -t `basename $0` "$MESSAGE"
    fi
  fi
  if [ $VERBOSE = "true" ]; then
    echo `basename $0` "$MESSAGE"
  fi
  return 0
}

function saveConfiguration {
  if [ -n "$1" ]; then
    sed -i -e "s/^KEY=.*$/KEY=$1/" "$CONFIG"
    if [ $VERBOSE = "true" ]; then
      echo "Saving KEY to configuration file"
    fi
  fi

  if [ -n "$2" ]; then
    sed -i -e "s/^RECORD=.*$/RECORD=$2/" "$CONFIG"
    if [ $VERBOSE = "true" ]; then
      echo "Saving RECORD to configuration file"
    fi

  fi
  if [ -n "$3" ]; then
    sed -i -e "s/^LOGGING=.*$/LOGGING=$3/" "$CONFIG"
    if [ $VERBOSE = "true" ]; then
      echo "Saving LOGGING to configuration file"
    fi
  fi
  return 0
}

function expandIPV6 {
  local IPV6=$1
  if [[ $IPV6 == *":"* ]]; then
    IPV6=`echo $IPV6 | awk '{if(NF<8){inner = "0"; for(missing = (8 - NF);missing>0;--missing){inner = inner ":0"}; if($2 == ""){$2 = inner} else if($3 == ""){$3 = inner} else if($4 == ""){$4 = inner} else if($5 == ""){$5 = inner} else if($6 == ""){$6 = inner} else if($7 == ""){$7 = inner}}; print $0}' FS=":" OFS=":" | awk '{for(i=1;i<9;++i){len = length($(i)); if(len < 1){$(i) = "0000"} else if(len < 2){$(i) = "000" $(i)} else if(len < 3){$(i) = "00" $(i)} else if(len < 4){$(i) = "0" $(i)} }; print $0}' FS=":" OFS=":"`
  fi
  echo "$IPV6"
}


VERBOSE="false"
LISTONLY="false"
declare -A TYPES=(["4"]="A" ["6"]="AAAA")
declare -A REGEXPS=(["4"]='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
		    ["6"]='^(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))'$)

declare -A OPTIP
declare -A IP
declare -A RECORDS

#Get Command Line Options
while getopts "L:4:6:k:r:Sdvl" OPTS
do
  case $OPTS in
    L)
    if ! ([ "$OPTARG" == "true" ] || [ "$OPTARG" == "false" ])  ; then
      echo `basename $0` " Invalid Parameters -- L"
      logStatus "error" "Invalid Parameters -- L"
      usage
      exit 1
    fi

    OPTLOGGING=$OPTARG
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

    4)
    if [[ $OPTARG =~ REGEXPS["4" ]];
    then
      OPTIP["4"]=$OPTARG
    else
      echo `basename $0` " Invalid Parameters -- 4"
      logStatus "error" "Invalid Parameters -- 4"
      usage
      exit 1
    fi
    ;;

    6)
    if [[ $OPTARG =~ REGEXPS["6" ]];
    then
      OPTIP["6"]=$(expandIPV6 $OPTARG)
    else
      echo `basename $0` " Invalid Parameters -- 6"
      logStatus "error" "Invalid Parameters -- 6"
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

if [ ! -f ~/.config/dynamicdns ]; then
  logStatus "notice" "Configuration File Not Found. Creating new configuration file."
  createConfigurationFile
fi

# Load Configuration File

source ~/.config/dynamicdns

# check for dependencies, if wget not available, test for curl, set variable to be used to test this later
if command -v wget >/dev/null 2>&1; then
  POSTPROCESS="wget"

elif command -v curl >/dev/null 2>&1; then
  POSTPROCESS="curl"

else
  echo `basename $0` "ERROR: Missing dependency -- wget or curl"
  logStatus "error" "Missing Dependency -- wget or curl"
  exit 1
fi
if [ $VERBOSE = "true" ]; then
  echo "Post process set to: $POSTPROCESS"
fi

if [ ! -n "$OPTKEY" ]; then
  if [ ! -n "$KEY" ]; then
    echo `basename $0` ": missing parameter -- KEY"
    logStatus "error" "Missing Parameter -- KEY"
    usage
    exit 1
  fi
else KEY="$OPTKEY"
fi

if [ ! -n "$OPTRECORD" ]; then
  if [ ! -n "$RECORD" ]; then
    echo `basename $0` ": missing parameter -- RECORD"
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

for TYPE in 4 6; do
  if [ ! -n "${OPTIP[$TYPE]}" ]; then
    if [ $VERBOSE = "true" ]; then
      echo "No IPV$TYPE Address provided, obtaining public IP"
    fi
    # Try multiple resolvers (in case they don't respond)
    RESOLVERS="
      o-o.myaddr.l.google.com:ns1.google.com:TXT
      myip.opendns.com:resolver1.opendns.com:$TYPE
      whoami.akamai.net:ns1-1.akamaitech.net:$TYPE
      o-o.myaddr.l.google.com:ns2.google.com:TXT
      myip.opendns.com:resolver2.opendns.com:$TYPE
      o-o.myaddr.l.google.com:ns3.google.com:TXT
      myip.opendns.com:resolver3.opendns.com:$TYPE
      o-o.myaddr.l.google.com:ns4.google.com:TXT
      myip.opendns.com:resolver4.opendns.com:$TYPE
    "
    for ENTRY in $RESOLVERS; do
      IFS=':' read -r OWN_HOSTNAME RESOLVER DNS_RECORD <<< "$ENTRY"
      IP46=$(dig -$TYPE +short $DNS_RECORD $OWN_HOSTNAME @$RESOLVER)
      if [ $? -eq 0 ]; then
	break
      fi
      logStatus "notice" "Failed to obtain current IPV$TYPE address using $RESOLVER"
    done
    IP46=${IP46//\"/}
    IP46=`echo "$IP46" | tr '{[:upper:]' '{[:lower:]}'`
    IP46=$(expandIPV6 $IP46)
    if [[ ! $IP46 =~ ${REGEXP[$TYPE]} ]]; then
      logStatus "error" "Failed to obtain current IPV$TYPE address"
      exit 3
    fi
    if [ $VERBOSE = "true" ]; then
      IP[$TYPE]=$IP46
      echo "Found current public IPV$TYPE: $IP46"
    fi
  else IP[$TYYPE]="${OPTIP[$TYPE]}"
  fi
done

function submitApiRequest {
  local KEY=$1
  local CMD=$2
  local ARGS=$3

  # Send request
  if [ $POSTPROCESS = "wget" ]; then
      local RESPONSE=$(wget -O- -q https://api.dreamhost.com/ \
        --post-data key=$KEY\&unique_id=$(uuidgen)\&cmd=$CMD\&$ARGS )
  elif [ $POSTPROCESS = "curl" ]; then
    local RESPONSE=$(curl -s --data "key=$KEY&unique_id=$(uuidgen)&cmd=$CMD&$ARGS" https://api.dreamhost.com/)
  else
    logStatus "error" "Missing Dependency -- wget or curl"
    exit 1
  fi
  local RC=$?

  # Output response
  printf "$RESPONSE"

  if [ $RC -ne 0 ]; then
    logStatus "notice" "API Request Failed"
    return $?
  fi

  # If "success" is not in the response, then the request failed
  printf "$RESPONSE" | grep "^success$" > /dev/null
}

function listRecord {
  local TYPE=$1

  # See whether there is already a record for this domain

  if [ ! "${RECORDS[$TYPE]}" ]; then
    logStatus "notice" "No IPV$TYPE Records"
    return 1
  fi

  local OLD_VALUE=`printf "${RECORDS[$TYPE]}" | awk '{print tolower($5) }'`
  OLD_VALUE=$(expandIPV6 $OLD_VALUE)

  echo "Found current IPV$TYPE record: $OLD_VALUE"

}

function deleteRecord {
  local TYPE=$1
  local NEW_VALUE=$2

  local OLD_VALUE=`echo ${RECORDS[$TYPE]} | awk '{print tolower($5) }'`
  OLD_VALUE=$(expandIPV6 $OLD_VALUE)

  if [ "$OLD_VALUE" == "$NEW_VALUE" ]; then
    # The current record is up to date, so we don't need to do anything
    return 255
  fi

  # We need to remove the existing record to continue

  submitApiRequest $KEY \
                   dns-remove_record \
                   record=$RECORD\&type=${TYPES[$TYPE]}\&value=$OLD_VALUE

  if [ $? -ne 0 ]; then
    logStatus "error" "Unable to Remove Existing Record"
    return 2
  else
    return 0
  fi
}


function addRecord {
  local TYPE=$1
  local KEY=$2
  local RECORD=$3
  local IP=$4

  submitApiRequest $KEY \
                   dns-add_record \
                   record=$RECORD\&type=${TYPES[$TYPE]}\&value=$IP
}

# dreamhost returns all records, disregarding any type or editable args!

function listRecords {
  local KEY=$1
  local RECORD=$2

  local LIST_RESP=`submitApiRequest $KEY dns-list_records`

  if [ $? -ne 0 ]; then
    logStatus "notice" "Error Listing Records: $LIST_RESP"
    exit 1
  fi

  local CLEANED_RECORD=`echo $RECORD | sed "s/[*]/[*]/g ; s/[.]/[.]/g "`
  for TYPE in 4 6; do
    RECORDS[$TYPE]=`printf "$LIST_RESP" | grep "\s$CLEANED_RECORD\s${TYPES[$TYPE]}\s${REGEXP[$TYPE]}"`
  done

}

# -------------------------------
# Main execution

listRecords $KEY $RECORD

for TYPE in 4 6; do
  if [ ! "${RECORDS[$TYPE]}" ]; then
    logStatus "notice" "No IPV$TYPE Records"
    continue
  fi

  if [ "$LISTONLY" == "true" ]; then

    # We're just getting the current record

    listRecord $TYPE

    if [ $? -ne 0 ]; then
      # Something is wrong
      logStatus "error" "ERROR $?"
      exit $?
    fi

  else

    # We're updating the record

    # Delete any existing record for this domain
    deleteRecord $TYPE ${IP[$TYPE]}

    if [ $? -eq 255 ]; then
      logStatus "notice" "IPV$TYPE Record up to date"
      continue
    fi

    if [ $? -ne 0 ]; then
      # Something is wrong
      logStatus "error" "ERROR $?"
      continue
    fi

    # Add the new record

    addRecord $TYPE $KEY $RECORD ${IP[$TYPE]}
    if [ $? -ne 0 ]; then
      logStatus "alert" "Failed to add new record"
      # In this case, if we have deleted the record, then you will no longer
      # have a DNS record for this domain.
      continue
    else
      logStatus "notice" "Record updated succesfully"
    fi

  fi
done

# Woohoo! We're exiting cleanly
exit 0
