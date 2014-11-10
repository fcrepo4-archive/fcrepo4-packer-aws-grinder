#! /bin/bash

echo ""
echo "Shutting down Grinder Agents..."
echo ""
for FILE in `ls ec2-agent-*.instance`; do
  INSTANCE=`cat $FILE`
  RESULT=`aws ec2 stop-instances --instance-ids $INSTANCE`
  RESULT=`aws ec2 terminate-instances --instance-ids $INSTANCE`
  echo "  $INSTANCE stopped and terminated"
done
echo ""
echo "Shutting down Grinder Console..."
echo ""
INSTANCE=`cat ec2-console.instance`
RESULT=`aws ec2 stop-instances --instance-ids $INSTANCE`
echo "  $INSTANCE stopped"
echo ""
echo "Grinder Console instance available for the next run"
echo ""