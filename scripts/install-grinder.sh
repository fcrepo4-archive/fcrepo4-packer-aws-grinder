#! /bin/bash

# Check whether what we have is a valid IPv4 address
function is_valid_ip() {
  local  ip=$1
  local  stat=1

  if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    OIFS=$IFS
    IFS='.'
    ip=($ip)
    IFS=$OIFS
    [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
    stat=$?
  fi

  return $stat
}

# Start up our Grinder Console or Grinder Agent AMI instance
if [ "$GRINDER_TYPE" == "console" ]; then
  # Leave hint of Grinder type so init.d script knows what type of service to start
  sudo mkdir /etc/grinder
  echo "console" | sudo tee /etc/grinder/type
  # Cf. http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html
  CONSOLE_HOST=`wget -O - -q http://169.254.169.254/latest/meta-data/public-hostname`
  echo "Starting Grinder Console running on ${CONSOLE_HOST}"
  # Start up the Grinder console and configure it to listen on the public port
  nohup java -Djava.net.preferIPv4Stack=true -Dgrinder.console.httpHost=${CONSOLE_HOST} \
      -classpath "/opt/grinder/lib/*" net.grinder.Console -headless &
  # Perform a little cleanup before finishing creation of the AMI
  rm nohup.out
elif [ "$GRINDER_TYPE" == "agent" ]; then
  sudo mkdir /etc/grinder
  # Leave hint of Grinder type so init.d script knows what type of service to start
  echo "agent" | sudo tee /etc/grinder/type >/dev/null
  # Agents need to be able to look up the IP of their console (private IPs persist in AWS VPCs but not in EC2-Classic)
  # So, for our purpose of connecting agents to the console, we'll have to look up the console instance's IP address.
  if [ -z $AWS_ACCESS_KEY ] || [ -z $AWS_SECRET_KEY ] || [ -z $AWS_REGION ]; then
    echo "Grinder installation can not take place without an AWS access key, secret key, and region"
    exit 1
  fi

  # We store these credentials on the Agent VMs, which don't have public IPs and just the default assigned SSH key
  # An alternative would be for the script to create an Elastic IP which would persist between builds / runs (TODO?)
  mkdir ~/.aws
  printf "[default]\naws_access_key_id = ${AWS_ACCESS_KEY}\naws_secret_access_key = ${AWS_SECRET_KEY}\noutput = text\nregion = ${AWS_REGION}\n" | tee -a ~/.aws/config >/dev/null
  chmod 750 ~/.aws
  chmod 660 ~/.aws/config
  sudo mkdir -p /var/www/.aws
  sudo ln -s ~/.aws/config /var/www/.aws/config
  sudo chown -R ubuntu:www-data /var/www/.aws ~/.aws

  if [ -z $GRINDER_CONSOLE_INSTANCE ]; then
    echo "Grinder Agent AMI can not be created without knowing the Grinder Console's AWS instance-id"
    exit 1
  else
    echo $GRINDER_CONSOLE_INSTANCE | sudo tee /etc/grinder/console.instance
  fi

  if [ -z $AWS_SECURITY_GROUP_ID ]; then
    echo "AWS security group ID isn't configured; Grinder Agents can't be configured to start without this"
    exit 1
  else
    echo $AWS_SECURITY_GROUP_ID | sudo tee /etc/grinder/ec2.sgid
  fi

  # Get the public IP where the console is running [FIXME: copy and paste here that should be externalized function]
  INSTANCE=`cat /etc/grinder/console.instance`
  if [ `aws ec2 describe-instances --instance-id ${INSTANCE} --filters Name=virtualization-type,Values=hvm \
      | grep -c INSTANCES` == 1 ]; then
    IP_INDEX=15
  elif [ `aws ec2 describe-instances --instance-id ${INSTANCE} --filters Name=virtualization-type,Values=paravirtual \
      | grep -c INSTANCES` == 1 ]; then
    IP_INDEX=16
  else
    echo "ERROR: Did not find the expected console instance: ${INSTANCE}"
    exit 1
  fi
  # END OF COPY AND PASTE BLOCK

  GRINDER_CONSOLE_IP=`aws ec2 describe-instances --filters Name=instance-id,Values=${INSTANCE} \
      | grep INSTANCES | cut -f ${IP_INDEX}`

  # Agents connect to console through the local (not public) EC2 network
  GRINDER_AGENT_IP=`wget -O - -q http://169.254.169.254/latest/meta-data/local-ipv4`

  # Surely the Console has received its public IP by the time this runs (or do we need to poll for it?)  
  if ! is_valid_ip $GRINDER_CONSOLE_IP; then
    echo "Console (${GRINDER_CONSOLE_INSTANCE})'s IP (${GRINDER_CONSOLE_IP}) does not seem to be valid"
    exit 1
  fi

  # Check that the grinder agent IP we received is actually a real IP
  if ! is_valid_ip $GRINDER_AGENT_IP; then
    echo "Console Agent's IP (${GRINDER_AGENT_IP}) does not seem to be valid"
    exit 1
  fi

  # Allow our spin-up agent instance to connect to the console (this is not a permanent agent)
  aws ec2 authorize-security-group-ingress --group-id `cat /etc/grinder/ec2.sgid` --protocol tcp --port 6372 \
      --cidr ${GRINDER_AGENT_IP}/32

  # Spin up an agent instance to confirm we can connect to the console
  # FIXME: Now hardcoded for PV virtualization type IP position; handle HVM virtualization too?
  HOST=`aws ec2 describe-instances --filters Name=instance-id,Values=${INSTANCE} | grep INSTANCES | cut -f 15`
  nohup java -Dgrinder.console.Host="$HOST" -classpath "/opt/grinder/lib/*" net.grinder.Grinder &

  # Give it a chance to output, if it's not there...
  if [ -f nohup.out ]; then
    sleep 30
  fi

  # Test that the connection was made
  if grep -Fq "waiting for console signal" nohup.out; then
    echo "Successfully connected agent to console"

    # Perform a little cleanup before finishing creation of the AMI
    rm nohup.out
  else
    echo "Failed to connect agent to console"
    exit 1
  fi

  # Revoke the agents access to the console now that we're done with it
  aws ec2 revoke-security-group-ingress --group-id `cat /etc/grinder/ec2.sgid` --protocol tcp --port 6372 \
      --cidr ${GRINDER_AGENT_IP}/32
else
  "ERROR: The start_grinder.sh script needs to be started as 'console' or 'agent'"
  exit 1
fi