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
INSTANCE=`cat ec2-console.instance`
RESULT=`aws ec2 stop-instances --instance-ids $INSTANCE 2>&1`
echo "  $INSTANCE stopped"

# Clean up all the project artifacts
if [ "$1" == "clean" ]; then
  RESULT=`aws ec2 terminate-instances --instance-ids $INSTANCE 2>&1`
  echo "  $INSTANCE terminated"

  # TODO: Clean AMIs and related snapshots

  rm -f *-build.log
  rm -f *.instance
  rm -f *.ami
else
  echo ""
  echo "Grinder Console instance is now available for the next run"
fi

echo ""