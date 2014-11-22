#! /bin/bash

#
# A little script to stop and clean up artifacts created by the project.
#
# Usage:
#   ./start.sh [terminate | clean]
#
# For instance:
#   ./start.sh
#   ./start.sh terminate
#   ./start.sh clean
#
# Author: Kevin S. Clarke <ksclarke@gmail.com>
# URL: http://github.com/ksclarke/packer-aws-grinder
#

function clean_up_ami {
  if [ -f $1 ]; then
    AMI=`cat ${1}`

    if [[ "$1" == *console* ]]; then
      AMI_TYPE="Console"
    elif [[ "$1" == *agent* ]]; then
      AMI_TYPE="Agent"
    else
      echo "ERROR: Don't recognize the type of the AMI to clean up"
      exit 1
    fi

    if [[ "$AMI" == ami* ]]; then
      aws ec2 deregister-image --image-id $AMI
      echo ""
      echo "$AMI_TYPE AMI (${AMI}) cleaned up"

      AMI_SNAP=`aws ec2 describe-snapshots --filters Name=description,Values=*${AMI}* | cut -f 6`

      if [[ "$AMI_SNAP" == snap* ]]; then
        aws ec2 delete-snapshot --snapshot-id $AMI_SNAP
        echo "$AMI_TYPE AMI snapshot (${AMI_SNAP}) cleaned up"
      fi
    else
      echo "Failed to find AMI details for ${1}"
      exit 1
    fi
  fi
}

# Shutdown up the agent instances
echo ""
echo "Shutting down Grinder Agents..."
echo ""
for FILE in `ls ec2-agent-*.instance 2>/dev/null`; do
  INSTANCE=`cat $FILE`
  RESULT=`aws ec2 stop-instances --instance-ids $INSTANCE 2>&1`

  if [[ "$1" == "terminate" || "$1" == "clean" ]]; then
    RESULT=`aws ec2 terminate-instances --instance-ids $INSTANCE 2>&1`
    rm -f "$FILE"
    echo "  $INSTANCE stopped and terminated"
  else
    echo "  $INSTANCE stopped"
  fi
done

# Shutdown the console instance
echo ""
echo "Shutting down Grinder Console..."
echo ""
if [ -f ec2-console.instance ]; then
  INSTANCE=`cat ec2-console.instance`
  RESULT=`aws ec2 stop-instances --instance-ids $INSTANCE 2>&1`
  echo "  $INSTANCE stopped"
fi

# Clean up all the project artifacts
if [ "$1" == "clean" ]; then
  if [ -f ec2-console.instance ]; then
    RESULT=`aws ec2 terminate-instances --instance-ids $INSTANCE 2>&1`
    echo "  $INSTANCE terminated"
  fi

  clean_up_ami "ec2-console.ami"
  clean_up_ami "ec2-agent.ami"

  rm -f *-build.log
  rm -f *.instance
  rm -f *.ami

  echo ""
  echo "All the project's artifacts have been cleaned up"
else
  echo ""
  echo "Grinder Console instance is now available for the next run"
fi

echo ""