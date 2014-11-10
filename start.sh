#! /bin/bash

#
# Starts a Grinder EC2 cloud up using the previously created Grinder Console instance and Grinder Agent AMI.
#
# Usage:
#   ./start.sh [NUMBER_OF_AGENTS]
#   ./start.sh 3
#
# Author: Kevin S. Clarke <ksclarke@gmail.com>
# URL: http://github.com/ksclarke/packer-aws-grinder
#

# First, we have to check our arguments to make sure we have what we need to run
if [ -z "$1" ]; then
  echo "You must start the script with the number of agents to spin up"
  echo "  Usage: ./start.sh 3"
  exit 1
fi

# Test that the number of agents we want to spin up is an integer
if [[ ! $1 =~ ^-?[0-9]+$ ]]; then
  echo "Supplied argument (number of agents to start) must be an integer"
  exit 1
fi

# Test to make sure we have all the external variables we need
if [ ! -e vars/vars.json ] || [ ! -e vars/agent-vars.json ] || [ ! -e vars/console-vars.json ]; then
  if [ ! -e vars/vars.json ]; then cp vars/example-vars.json vars/vars.json; fi
  if [ ! -e vars/console-vars.json ]; then cp vars/example-console-vars.json vars/console-vars.json; fi
  if [ ! -e vars/agent-vars.json ]; then cp vars/example-agent-vars.json vars/agent-vars.json; fi
  echo "  Please edit the project's vars.json, console-vars.json, and agent-vars.json files before running this script"
  echo "   You may leave *_password variables blank if you want them to be filled with automatically generated values"
  exit 1
fi

# Test that we've already run the build.sh script
if [ ! -f ec2-console.instance ]; then
  echo "There isn't an 'ec2-console.instance' file in the project directory"
  echo "  You need to run the ./build.sh script before running ./start.sh"
  exit 1
fi

# A function that waits until the supplied instance is up and running
function wait_for_instance {
  # To wait until console instance is in a "running" state, we first need to know what type of virtualization we're using
  if [ `aws ec2 describe-instances --instance-id ${1} --filters Name=virtualization-type,Values=hvm | grep -c INSTANCES` == 1 ]; then
    IP_INDEX=15
  elif [ `aws ec2 describe-instances --instance-id ${1} --filters Name=virtualization-type,Values=paravirtual | grep -c INSTANCES` == 1 ]; then
    IP_INDEX=16
  else
    echo "ERROR: Did not find the expected console instance: ${1}"
    exit 1
  fi

  # Now, we keep checking for a public IP (which means the console is up and running, and accessible by our agents)
  for i in {1..300}; do
    echo `aws ec2 describe-instances --instance-id ${1} --filters Name=instance-state-name,Values=running | grep INSTANCES | cut -f $IP_INDEX` | tee /tmp/ec2-console.ip >/dev/null
    if [[ `cat /tmp/ec2-console.ip` =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
      # Once we have a public IP, we know it's up and running and can continue
      break
    fi
  done
}

# Not a great way to parse JSON, but it doesn't require any additional software to be installed (like jsawk, etc.)
function extract_from_json {
  export ${1}=`grep -Po "\"${2}\": ?\".*\"," vars/${3}.json | sed "s/\"${2}\": \"//" | sed "s/\",//"`
}

# Start up our Grinder Console instance
RESULT=`aws ec2 start-instances --instance-ids $(cat ec2-console.instance)`
wait_for_instance $(cat ec2-console.instance)
echo "Started Grinder Console ... $(cat ec2-console.instance)"

# We need to read our JSON config files to get the values needed to start the Grinder Agents
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
   extract_from_json "AWS_INSTANCE_TYPE" "aws_instance_type" "console-vars"
fi

# Spin up the requested number of Grinder Agents (they will be automatically connected to the Console)
for index in $(seq 1 $1); do
  # --no-associate-public-ip-address [temporarily removed to aid debugging]
  echo `aws ec2 run-instances --image-id $(cat ec2-agent.ami) --security-group-ids "${AWS_SECURITY_GROUP_ID}" \
  --key-name "${AWS_KEYPAIR_NAME}" --instance-type "${AWS_INSTANCE_TYPE}"  \
  --placement "AvailabilityZone=${AWS_REGION}a" | grep INSTANCES | cut -f 8` | tee ec2-agent-${index}.instance \
  >/dev/null
  wait_for_instance $(cat ec2-agent-${index}.instance)
  echo "Started Grinder Agent #${index} ... $(cat ec2-agent-${index}.instance)"
done