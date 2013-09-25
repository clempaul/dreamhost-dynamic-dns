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

if [ -f ~/.config/dynamicdns ]; then
  source ~/.config/dynamicdns
fi

if [ "$KEY" == "" ]; then
  echo "Missing KEY configuration option"
  exit 100
fi

if [ "$RECORD" == "" ]; then
  echo "Missing RECORD configuration option"
  exit 101
fi

function submitApiRequest {
  local KEY=$1
  local CMD=$2
  local ARGS=$3

  # Send request
  local RESPONSE=$(wget -O- -q https://api.dreamhost.com/ \
    --post-data key=$KEY\&unique_id=$(uuidgen)\&cmd=$CMD\&$ARGS )
  local RC=$?

  # Output response
  printf "$RESPONSE"

  if [ $RC -ne 0 ]; then
    echo "API Request failed"
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
    echo "Error listing records"
    printf "$LIST_RESP"
    return 1
  fi

  local CURRENT_RECORD=`printf "$LIST_RESP" | grep "\s$RECORD\sA"`

  if [ $? -ne 0 ]; then
    # Record not found
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
    echo "Unable to delete existing record"
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

# Get our current IP address

IP=`wget -O- -q http://software.clempaul.me.uk/ip.php`
if [ $? -ne 0 ]; then
  echo "Failed to get current IP address"
  exit 3
fi

# Delete any existing record for this domain and determine whether we
# even need to do any work

deleteRecord $KEY $RECORD $IP

if [ $? -eq 255 ]; then
  echo "Record up to date"
  exit 0
fi

if [ $? -ne 0 ]; then
  # Something is wrong
  exit $?
fi

# Add the new record

addRecord $KEY $RECORD $IP
if [ $? -ne 0 ]; then
  echo "FATAL ERROR: Failed to add new record"
  # In this case, if we have deleted the record, then you will no longer
  # have a DNS record for this domain.
  exit 4
else 
  echo "Record updated succesfully"
fi

# Woohoo! We're exiting cleanly
exit 0
