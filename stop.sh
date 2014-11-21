#! /bin/bash

# Shutdown up the agent instances
echo ""
echo "Shutting down Grinder Agents..."
echo ""
for FILE in `ls ec2-agent-*.instance 2>/dev/null`; do
  INSTANCE=`cat $FILE`
  RESULT=`aws ec2 stop-instances --instance-ids $INSTANCE 2>&1`

  if [ "$1" == "terminate" ]; then
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
echo ""
echo "Grinder Console instance is now available for the next run"
echo ""
