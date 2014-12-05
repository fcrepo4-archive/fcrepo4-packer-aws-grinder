#! /bin/bash

#
# A little script I use to run the Packer build because, among other reasons, I like to have comments in my JSON
# (documenting what everything is). But, that's not allowed:
#
#   https://plus.google.com/+DouglasCrockfordEsq/posts/RK8qyGVaGSr
#
# The script prefers to use `strip-json-comments` but will still work if there is a JSON artifact from an earlier build
# still around on the file system.
#
# The script creates two EC2 AMIs (one for a Grinder Console and one for a Grinder Agent).  It also creates an EC2
# Grinder Console instance that should be saved (because it is associated with the Grinder Agent AMI that is created).
# Agent instances should be created with the start.sh script (and they will be automatically connected to the Console).
#
# Author: Kevin S. Clarke <ksclarke@gmail.com>
# URL: http://github.com/ksclarke/packer-aws-grinder
#

# Create a logs directory if it doesn't already exist
mkdir -p logs

# Clean up artifacts from previous builds
rm -f logs/*-build.log
rm -f *.instance
rm -f *.ami

# If we have strip-json-comments installed, we can build from the JSON source file
STRIP_JSON_SCRIPT=`which strip-json-comments`

# Test to make sure we have all the external variables we need
if [ ! -e vars/vars.json ] || [ ! -e vars/agent-vars.json ] || [ ! -e vars/console-vars.json ]; then
  if [ ! -e vars/vars.json ]; then cp vars/example-vars.json vars/vars.json; fi
  if [ ! -e vars/console-vars.json ]; then cp vars/example-console-vars.json vars/console-vars.json; fi
  if [ ! -e vars/agent-vars.json ]; then cp vars/example-agent-vars.json vars/agent-vars.json; fi
  echo "  Please edit the project's vars.json, console-vars.json, and agent-vars.json files before running this script"
  echo "   You may leave *_password variables blank if you want them to be filled with automatically generated values"
  exit 1
fi

# We supply random password values to any variables ending with "_password"
function check_file_vars {
  # Looks to see if the vars file has any empty passwords; creates passwords if needed
  while read LINE; do
    if [ ! -z "$LINE" ]; then
      REPLACEMENT="_password\": \"`openssl rand -base64 12`\""

      if [[ ! -e .passwords ]]; then
        PASSWORD_PATTERN="_password\": \"\""
      else
        PASSWORD_PATTERN="_password\": \"*\""
      fi

      NEWLINE="${LINE/$PASSWORD_PATTERN/$REPLACEMENT}"

      if [ "$NEWLINE" != "$LINE" ]; then
        touch .passwords
      fi

      echo $NEWLINE
    fi
  done <vars/${1}.json > vars/${1}.json.new
  mv vars/${1}.json.new vars/${1}.json
}

# We eat the validation output unless it's an error
function validate_json {
  RESULT=`packer validate -var-file=vars/vars.json -var-file=vars/${1}-vars.json aws-grinder.json`

  if [ "$RESULT" != "Template validated successfully." ]; then
    echo -e "\n$RESULT"
    exit 1
  fi
}

# The main work of the script -- if we're not running in CI, use vars files; else, use ENV vars
function build_aws_grinder {
  if [ -z "$CONTINUOUS_INTEGRATION" ]; then
    check_file_vars "${1}-vars"
    validate_json "$1"
    packer build -var-file="vars/vars.json" -var-file="vars/${1}-vars.json" -var "grinder_type=${1}"  \
      -var "aws_public_ip=${2}" -var "grinder_console_instance=${3}" aws-grinder.json \
      | tee logs/aws-grinder-${1}-build.log
  else
    # TODO: We don't use vars files, but supply variables on the command line
    packer -machine-readable build \
      aws-grinder.json | tee logs/aws-grinder-${1}-build.log
  fi
}

# Not great, but doesn't require any additional software to be installed (like jsawk, etc.)
function extract_from_json {
  export ${1}=`grep -Po "\"${2}\": ?\".*\",?" vars/${3}.json | sed "s/\"${2}\": \"//" | tr -d "\","`
}

# If we're not running as a part of a CI process, we need to pre-process our vars files
if [ -z "$CONTINUOUS_INTEGRATION" ]; then
  check_file_vars "vars"
fi

# If we have strip-json-comments installed, use JSON source file; else use previously generated aws-grinder.json
if [ ! -f $STRIP_JSON_SCRIPT ]; then
  strip-json-comments packer-aws-grinder.json > aws-grinder.json
elif [ ! -f aws-grinder.json ]; then
  echo "  strip-json-comments needs to be installed to generate the aws-grinder.json file"
  echo "    For installation instructions, see https://github.com/sindresorhus/strip-json-comments"
  exit 1
fi

# Run the Packer.io build for our Grinder Console AMI; "true" gives it a public IP address
build_aws_grinder "console" "true"

# We need to find out the Grinder Console's AMI so we can launch and pass the instance to the Agents
if grep -q 'Builds finished but no artifacts were created' logs/aws-grinder-console-build.log; then exit 1; fi
echo `awk '{ print $NF }' logs/aws-grinder-console-build.log | tail -n 1 | tr -d '\n'` | tee ec2-console.ami >/dev/null

# We need to read our JSON config files to get the values for the arguments to: aws ec2 run-instances
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

# Go ahead and spin up the Grinder Console instance so the Grinder Agents know how to connect to it
echo `aws ec2 run-instances \
  --image-id $(cat ec2-console.ami) --security-group-ids "${AWS_SECURITY_GROUP_ID}" \
  --key-name "${AWS_KEYPAIR_NAME}" --instance-type "${AWS_INSTANCE_TYPE}" \
  --placement "AvailabilityZone=${AWS_REGION}a" | grep INSTANCES | cut -f 8` | tee ec2-console.instance >/dev/null

# Run the Packer.io build for our Grinder Agent AMI; "false" gives it a private (rather than public) IP
build_aws_grinder "agent" "false" `cat ec2-console.instance`

# We need to find out the Grinder Agent's AMI so we can launch instances later from our start.sh script
if grep -q 'Builds finished but no artifacts were created' logs/aws-grinder-agent-build.log; then exit 1; fi
echo `awk '{ print $NF }' logs/aws-grinder-agent-build.log | tail -n 1 | tr -d '\n'` | tee ec2-agent.ami >/dev/null

# Lastly, we stop our console instance but do not terminate it; it will be reused when we run the grinder cloud
RESULT=`aws ec2 stop-instances --instance-ids $(cat ec2-console.instance)`
