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
	echo 'usage:   dynamicdns.bash [-Sdv][-k API Key] [-r Record] [-i New IP Address] [-L Logging (true/false)]'
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
			logger -p syslog.err -t "dynamicdns.bash" "$MESSAGE"
		elif [ $LEVEL = "notice" ]; then
			logger -p syslog.notice -t "dynamicdns.bash" "$MESSAGE"
		elif [ $LEVEL = "alert" ]; then
			logger -p syslog.alert -t "dynamicdns.bash" "$MESSAGE"
		fi
	fi
	if [ $VERBOSE = "true" ]; then
		echo "dynamicdns.bash $MESSAGE"
	fi
	return 0
}

function saveConfiguration {
	if [ -n "$1" ]; then
		sed -i "" -e "s/^KEY=.*$/KEY=$1/" "$CONFIG"
		if [ $VERBOSE = "true" ]; then
			echo "Saving KEY to configuration file"
		fi
	fi

	if [ -n "$2" ]; then
		sed -i "" -e "s/^RECORD=.*$/RECORD=$2/" "$CONFIG"
		if [ $VERBOSE = "true" ]; then
			echo "Saving RECORD to configuration file"
		fi

	fi
	if [ -n "$3" ]; then
		sed -i "" -e "s/^LOGGING=.*$/LOGGING=$3/" "$CONFIG"
		if [ $VERBOSE = "true" ]; then
			echo "Saving LOGGING to configuration file"
		fi
	fi
	return 0
}

VERBOSE="false"
LISTONLY="false"
#Get Command Line Options
while getopts "L:i:k:r:Sdvl" OPTS
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

		i)
			if [[ $OPTARG =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]];
			then
				OPTIP=$OPTARG
			else
				echo `basename $0` " Invalid Parameters -- i"
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
		echo "dynamicdns.bash: missing parameter -- KEY"
		logStatus "error" "Missing Parameter -- KEY"
		usage
		exit 1
	fi
else KEY="$OPTKEY"
fi

if [ ! -n "$OPTRECORD" ]; then
	if [ ! -n "$RECORD" ]; then
		echo "dynamicdns.bash: missing parameter -- RECORD"
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

if [ ! -n "$OPTIP" ]; then
	if [ $VERBOSE = "true" ]; then
		echo "No IP Address provided, obtaining public IP"
	fi
	IP=$(eval "dig -4 +short myip.opendns.com @resolver1.opendns.com")
	if [ $? -ne 0 ]; then
		logStatus "error" "Failed to obtain current IP address"
		exit 3
	fi
	if [ $VERBOSE = "true" ]; then
		echo "Found current public IP: $IP"
	fi
else IP="$OPTIP"
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
  local KEY=$1
  local RECORD=$2

  # See whether there is already a record for this domain

  local LIST_RESP=`submitApiRequest $KEY dns-list_records type=A\&editable=1`

  if [ $? -ne 0 ]; then
    logStatus "notice" "Error Listing Records: $LIST_RESP"
    return 1
  fi

  local CLEANED_RECORD=`echo $RECORD | sed "s/[*]/[*]/g ; s/[.]/[.]/g "` 
  local CURRENT_RECORD=`printf "$LIST_RESP" | grep "\s$CLEANED_RECORD\sA"`

  if [ $? -ne 0 ]; then
    logStatus "error" "Record not found"
    return 0
  fi

  local OLD_VALUE=`printf "$CURRENT_RECORD" | awk '{print $5 }'`

	echo "Found current record: $OLD_VALUE"

}

function deleteRecord {
  local KEY=$1
  local RECORD=$2
  local NEW_VALUE=$3

  # See whether there is already a record for this domain

  local LIST_RESP=`submitApiRequest $KEY dns-list_records type=A\&editable=1`
  if [ $? -ne 0 ]; then
    logStatus "notice" "Error Listing Records: $LIST_RESP"
    return 1
  fi

  local CLEANED_RECORD=`echo $RECORD | sed "s/[*]/[*]/g ; s/[.]/[.]/g "` 
  local CURRENT_RECORD=`echo $LIST_RESP | egrep -o "\s$CLEANED_RECORD\s+A\s+[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}"`
  if [ $VERBOSE = "true" ]; then
    echo "Current Record: $CURRENT_RECORD"
  fi
  if [ $? -ne 0 ]; then
    logStatus "error" "Record not found"
    return 0
  fi

  local OLD_VALUE=`echo $CURRENT_RECORD | awk '{print $3 }'`

  if [ "$OLD_VALUE" == "$NEW_VALUE" ]; then
    # The current record is up to date, so we don't need to do anything
    return 255
  fi

  # We need to remove the existing record to continue

  submitApiRequest $KEY \
                   dns-remove_record \
                   record=$RECORD\&type=A\&value=$OLD_VALUE

  if [ $? -ne 0 ]; then
    logStatus "error" "Unable to Remove Existing Record"
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

# -------------------------------
# Main execution

if [ "$LISTONLY" == "true" ]; then

	# We're just getting the current record
	
	listRecord $KEY $RECORD

	if [ $? -ne 0 ]; then
		# Something is wrong
		logStatus "error" "ERROR $?"
		exit $?
	fi

else

        # We're updating the record

	# Delete any existing record for this domain
	deleteRecord $KEY $RECORD $IP

	if [ $? -eq 255 ]; then
	  logStatus "notice" "Record up to date"
	  exit 0
	fi

	if [ $? -ne 0 ]; then
	  # Something is wrong
	  logStatus "error" "ERROR $?"
	  exit $?
	fi

	# Add the new record

	addRecord $KEY $RECORD $IP
	if [ $? -ne 0 ]; then
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
