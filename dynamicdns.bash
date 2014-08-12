#!/bin/bash

# This script updates a DNS A record hosted by Dreamhost to your current IP
# address via the Dreamhost API.
#
# =============================================================================
#
# Copyright (c) 2013, Paul Clement
# All rights reserved.
#
# See LICENSE for more details.

function usage {
	echo 'usage:   dynamicdns.bash [-Sd][-k API Key] [-r Record] [-i New IP Address] [-L Logging (true/false)]'
}

function createConfigurationFile {

	if [ ! -d $HOME/.config ]; then
		echo "$HOME/.config/ does not exist, creating directory."
		mkdir $HOME/.config
	fi
	
echo '# Dreamhost Dynamic DNS Updater Configuration file.  This file
# allows you to set the basic parameters to update Dreamhost
# dynamic dns without command line options.
# There are three basic parameters:
#
# KEY
# This parameter is your Dreamhost API Key.  The parameter should
# be This key should be specified as a STRING.  Your API KEY must
# be given the the following permissions in the Dreamhost
# webpanel:
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

' >> $HOME/.config/dynamicdns

return 0
}

function saveConfiguration {
	if [ -n "$1" ]; then
		sed -i "" -e "s/^KEY=.*$/KEY=$1/" $HOME/.config/dynamicdns
	fi

	if [ -n "$2" ]; then
		sed -i "" -e "s/^RECORD=.*$/RECORD=$2/" $HOME/.config/dynamicdns
	fi
	if [ -n "$3" ]; then
		sed -i "" -e "s/^LOGGING=.*$/LOGGING=$3/" $HOME/.config/dynamicdns
	fi
	return 0
}

#Get Command Line Options
while getopts "L:i:k:r:Sd" OPTS
do
	case $OPTS in
		L)
		if ! ([ "$OPTARG" == "true" ] || [ "$OPTARG" == "false" ])  ; then
			echo `basename $0` " invalid argument -- L"
			logger -p syslog.err -t "dynamicdns.bash" "Invalid Parameters" -- L
			usage
			exit 1
		fi
		
		OPTLOGGING=$OPTARG
		;;
		
		k)
		OPTKEY=$OPTARG
		;;
		
		r)
		OPTRECORD=$OPTARG
		;;
		
		i)
			if [[ $OPTARG =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]];
			then
				OPTIP=$OPTARG
			else
				echo `basename $0` " invalid argument -- i"
				logger -p syslog.err -t "dynamicdns.bash" "Invalid Parameters -- i"
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
	logger -p syslog.notice -s -t "dynamicdns.bash" "Configuration File Not Found. Creating new configuration file."
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
	logger -p syslog.err -t "dynamicdns.bash" "Missing Dependency -- wget or curl"
	exit 1
fi


if [ ! -n "$OPTKEY" ]; then
	if [ ! -n "$KEY" ]; then
		echo "dynamicdns.bash: missing parameter -- KEY"
		logger -p syslog.err -t "dynamicdns.bash" "Missing Parameter -- KEY"
		usage
		exit 1
	fi
else KEY="$OPTKEY"
fi

if [ ! -n "$OPTRECORD" ]; then
	if [ ! -n "$RECORD" ]; then
		echo "dynamicdns.bash: missing parameter -- RECORD"
		logger -p syslog.err -t "dynamicdns.bash" "Missing Parameter -- RECORD"
		usage
 	exit 1
	fi
else RECORD="$OPTRECORD"
fi

if [ "$SAVE" == "true" ] || [ "$SAVEONLY" == "true" ]; then
	saveConfiguration "$OPTKEY" "$OPTRECORD" "$OPTLOGGING"
fi

if [ "$SAVEONLY" == "true" ]; then
	echo "Saving Configuration File and Exiting"
	exit 0
fi

if [ -n $OPTIP ]; then
	echo "No IP Address provided, obtaining public IP"
	IP=$(eval "dig +short myip.opendns.com @resolver1.opendns.com")
	if [ $? -ne 0 ]; then
		logger -p syslog.err -s -t "dynamicdns.bash" "Failed to obtain current IP address"
		exit 3
	fi
fi


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
		logger -p syslog.err -t "dynamicdns.bash" "Missing Dependency -- wget or curl"
		exit 1
	fi
	local RC=$?

  # Output response
  printf "$RESPONSE"

  if [ $RC -ne 0 ]; then
    logger -p syslog.notice -t "dynamicdns.bash" "API Request Failed"
    return $?
  fi

  # If "success" is not in the response, then the request failed
  printf "$RESPONSE" | grep "^success$" > /dev/null
}

function deleteRecord {
  local KEY=$1
  local RECORD=$2
  local NEW_VALUE=$3

  # See whether there is already a record for this domain

  local LIST_RESP=`submitApiRequest $KEY dns-list_records type=A\&editable=1`

  if [ $? -ne 0 ]; then
    logger -p syslog.notice -t "dynamicdns.bash" "Error Listing Records: $LIST_RESP"
    return 1
  fi

  local CURRENT_RECORD=`printf "$LIST_RESP" | grep "\s$RECORD\sA"`

  if [ $? -ne 0 ]; then
    logger -p syslog.err -t "dynamicdns.bash" "Record not found"
    return 0
  fi

  local OLD_VALUE=`printf "$CURRENT_RECORD" | awk '{print $5 }'`

  if [ "$OLD_VALUE" == "$NEW_VALUE" ]; then
    # The current record is up to date, so we don't need to do anything
    return 255
  fi

  # We need to remove the existing record to continue

  submitApiRequest $KEY \
                   dns-remove_record \
                   record=$RECORD\&type=A\&value=$OLD_VALUE

  if [ $? -ne 0 ]; then
    logger -p syslog.err -t "dynamicdns.bash" "Unable to Remove Existing Record"
    return 2
  else
    return 0
  fi
}

function addRecord {
  local KEY=$1
  local RECORD=$2
  local IP=$3

  submitApiRequest $KEY \
                   dns-add_record \
                   record=$RECORD\&type=A\&value=$IP
}

# Delete any existing record for this domain and determine whether we
# even need to do any work

deleteRecord $KEY $RECORD $IP

if [ $? -eq 255 ]; then
  logger -p syslog.notice -t "dynamicdns.bash" -s "Record up to date"
  exit 0
fi

if [ $? -ne 0 ]; then
  # Something is wrong
  logger -p syslog.err -t "dynamicdns.bash" "ERROR $?"
  exit $?
fi

# Add the new record

addRecord $KEY $RECORD $IP
if [ $? -ne 0 ]; then
	logger -p syslog.alert -t "dynamicdns.bash" "Failed to add new record"
  # In this case, if we have deleted the record, then you will no longer
  # have a DNS record for this domain.
  exit 4
else 
  logger -p syslog.notice -t "dynamicdns.bash" -s "Record updated succesfully"
fi

# Woohoo! We're exiting cleanly
exit 0
