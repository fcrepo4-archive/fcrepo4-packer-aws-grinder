#! /bin/bash

#
# Starts a Fedora instance for Grinder to run against.
#
# Usage:
#   ./fedora.sh [ start | stop | clean ]
#
# For instance:
#   ./fedora.sh start
#   ./fedora.sh stop
#   ./fedora.sh clean
#
# Author: Kevin S. Clarke <ksclarke@gmail.com>
# URL: http://github.com/fcrepo4-labs/packer-aws-grinder
#

# Allow a debug flag to be set for more detailed output
DEBUG=${DEBUG:-false}

# Number of times to check AWS status before giving up and declaring a failed process
# This is just a guess for now... more experience running this script may help refine this
MAX_ATTEMPTS=1000

# Test to make sure we have all the external variables we need
if [ ! -e vars/vars.json ] || [ ! -e vars/agent-vars.json ] || [ ! -e vars/console-vars.json ]; then
  if [ ! -e vars/vars.json ]; then cp vars/example-vars.json vars/vars.json; fi
  if [ ! -e vars/console-vars.json ]; then cp vars/example-console-vars.json vars/console-vars.json; fi
  if [ ! -e vars/agent-vars.json ]; then cp vars/example-agent-vars.json vars/agent-vars.json; fi
  echo "  Please edit the project's vars.json, console-vars.json, and agent-vars.json files before running this script"
  exit 1
fi

# Check that our JSON files are valid before continuing
function validate_json {
  RESULT=`packer validate -var-file=vars/vars.json -var-file=vars/${1}-vars.json aws-grinder.json`

  if [ "$RESULT" != "Template validated successfully." ]; then
    echo -e "\n$RESULT"
    exit 1
  fi
}

# A function that waits until the supplied instance is up and running
function wait_for_instance {
  FOUND=false

  # To wait until instance is in a "running" state, we first need to know what type of virtualization we're using
  if [ `aws ec2 describe-instances --instance-id ${1} --filters Name=virtualization-type,Values=hvm \
      | grep -c INSTANCES` == 1 ]; then
    IP_INDEX=15
  elif [ `aws ec2 describe-instances --instance-id ${1} --filters Name=virtualization-type,Values=paravirtual \
      | grep -c INSTANCES` == 1 ]; then
    IP_INDEX=16
  else
    echo "ERROR: Did not find the expected console instance: ${1}"
    exit 1
  fi

  # Configure whether we're checking for a private or public IP
  if [ "$2" == "private" ]; then
    OFFSET=2
  else
    OFFSET=0
  fi

  # Now, we keep checking for a public IP (which means the instance is accessible)
  for TRY in $(seq 1 $MAX_ATTEMPTS); do
    echo `aws ec2 describe-instances --instance-id ${1} --filters Name=instance-state-name,Values=running \
        | grep INSTANCES | cut -f $(($IP_INDEX - $OFFSET))` | tee /tmp/ec2-instance.ip >/dev/null

    if [[ `cat /tmp/ec2-instance.ip` =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
      FOUND=true
      break
    fi
  done

  # I could have it continue to check until it finds something (possibly creating an infinite loop?)
  # For now, I'm being more cautious, giving it a timeout, and having it report this error instead
  if [ "$FOUND" = false ]; then
    echo "ERROR: Checked ${1} but was unable to get an IP address"
    echo "  The instance may just be slow starting... please consult the AWS console"
    exit 1
  fi
}


# Not great, but doesn't require any additional software to be installed (like jsawk, etc.)
function extract_from_json {
  export ${1}=`grep -Po "\"${2}\": ?\".*\",?"? vars/${3}.json | sed "s/\"${2}\": \"//" | tr -d "\","`
}

function print_usage {
  echo "Please run this script with either a 'start' or 'stop' argument."
  echo "  Usage: ./fedora.sh [ start | stop | clean ]"
  exit 1
}

if [ -z "$1" ]; then
  print_usage
elif [ "$1" != "start" ] && [ "$1" != "stop" ] && [ "$1" != "clean" ]; then
  print_usage
else
  validate_json fedora
fi

# We need to read our JSON config files to get the values needed to start our Fedora instance
if [ -z "$AWS_REGION" ]; then
  extract_from_json "AWS_REGION" "aws_region" "vars"
fi
if [ -z "$AWS_SECURITY_GROUP_ID" ]; then
   extract_from_json "AWS_SECURITY_GROUP_ID" "aws_security_group_id" "vars"
fi
if [ -z "$AWS_KEYPAIR_NAME" ]; then
   extract_from_json "AWS_KEYPAIR_NAME" "aws_keypair_name" "vars"
fi
if [ -z "$AWS_INSTANCE_TYPE" ]; then
   extract_from_json "AWS_INSTANCE_TYPE" "aws_instance_type" "fedora-vars"
fi
if [ -z "$AWS_SOURCE_AMI" ]; then
  extract_from_json "AWS_SOURCE_AMI" "aws_source_ami" "fedora-vars"
fi

if [ "$1" == "start" ]; then
  if [ ! -f ec2-fedora.instance ]; then
    SG_NAME=`aws ec2 describe-security-groups --group-ids ${AWS_SECURITY_GROUP_ID} | head -n 1 | cut -f 4`
    PLACEMENT_GROUP="AvailabilityZone=${AWS_REGION}a"

    if [ "$DEBUG" == true ]; then
      echo "Creating EC2 Fedora instance"
      echo "  Public Fedora AMI: ${AWS_SOURCE_AMI}"
      echo "  Security group ID: ${AWS_SECURITY_GROUP_ID}"
      echo "  EC2 key pair name: ${AWS_KEYPAIR_NAME}"
      echo "  EC2 instance type: ${AWS_INSTANCE_TYPE}"
      echo "  AWS Region: ${AWS_REGION}"
      echo "  EC2 placement: ${PLACEMENT_GROUP}"
    fi

    # Go ahead and spin up the Grinder Console instance so the Grinder Agents know how to connect to it
    echo `aws ec2 run-instances \
      --image-id "${AWS_SOURCE_AMI}" --security-group-ids "${AWS_SECURITY_GROUP_ID}" \
      --key-name "${AWS_KEYPAIR_NAME}" --instance-type "${AWS_INSTANCE_TYPE}" \
      --placement "${PLACEMENT_GROUP}" | grep INSTANCES | cut -f 8` | tee ec2-fedora.instance >/dev/null

    wait_for_instance $(cat ec2-fedora.instance)
    # TODO: Sanity test to make sure Fedora/Tomcat is up (and not just the machine)
    echo "Running EC2 Fedora instance \"$(cat ec2-fedora.instance)\" at $(cat /tmp/ec2-instance.ip)"
  else
    INSTANCE=`cat ec2-fedora.instance`

    if [ "$DEBUG" == true ]; then
      echo "Starting pre-existing EC2 Fedora instance: ${INSTANCE}"
    fi

    # TODO: Confirm instance is in a stopped state before trying to start
    RESULT=`aws ec2 start-instances --instance-ids ${INSTANCE}`
    wait_for_instance ${INSTANCE}
    # TODO: Sanity test to make sure Fedora/Tomcat is up (and not just the machine)
    echo "Running EC2 Fedora instance \"$(cat ec2-fedora.instance)\" at $(cat /tmp/ec2-instance.ip)"
  fi
elif [ "$1" == "stop" ]; then
  INSTANCE=`cat ec2-fedora.instance`

  if [ "$DEBUG" == true ]; then
    echo "Stopping EC2 Fedora instance: ${INSTANCE}"
  fi

  RESULT=`aws ec2 stop-instances --instance-ids ${INSTANCE} 2>&1`
  echo "EC2 Fedora instance ${INSTANCE} successfully stopped"
elif [ "$1" == "clean" ]; then
  INSTANCE=`cat ec2-fedora.instance`

  if [ "$DEBUG" == true ]; then
    echo "Cleaning up EC2 Fedora instance: ${INSTANCE}"
  fi

  # First may not be necessary, but is included just in case; we eat any errors thrown
  RESULT=`aws ec2 stop-instances --instance-ids ${INSTANCE} 2>&1`
  RESULT=`aws ec2 terminate-instances --instance-ids ${INSTANCE} 2>&1`
  rm -f ec2-fedora.instance
else
  echo "ERROR: Unexpected script argument: ${1}"
  exit 1
fi