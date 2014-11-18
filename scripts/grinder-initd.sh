#!/bin/bash

#------------------------------------------------------------------------------
# grinder-initd v0.0.1
#------------------------------------------------------------------------------
# Script for running Grinder on EC2 as a service under initd. The
# AWS CLI must already be installed in order to use this script.
#
# Usage: service grinder {start|stop|restart|status}"
#
#------------------------------------------------------------------------------
# Author: Kevin S. Clarke <ksclarke@gmail.com>
# URL: https://github.com/ksclarke/packer-aws-grinder
#------------------------------------------------------------------------------
### BEGIN INIT INFO
# Provides: grinder
# Required-Start: $network
# Required-Stop: $network
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: init script for Packer AWS Grinder
# Description: init script for Packer AWS Grinder; should be copied to /etc/init.d
### END INIT INFO

GRINDER_HOME="/opt/grinder"
GRINDER_DATA_DIR="/tmp"
GRINDER_PIDFILE="/var/run/grinder.pid"
GRINDER_LOGFILE="/var/log/grinder-console.log"

# Find out what Linux distribution we're running under
DISTRIB_ID=`lsb_release -i |awk ' { print $3 }'`

# Try to correctly set the user who should be used to run the server
if [ "$TRAVIS" == 'true' ] ; then
  GRINDER_USER="$USER"
elif [ "$DISTRIB_ID" == 'RedHatEnterpriseServer' ] \
    || [ "$DISTRIB_ID" == 'RedHat' ] \
    || [ "$DISTRIB_ID" == 'Fedora' ] \
    || [ "$DISTRIB_ID" == 'CentOS' ] ; then
  GRINDER_USER="apache"
elif [ "$DISTRIB_ID" == 'Ubuntu' ] \
    || [ "$DISTRIB_ID" == 'Debian' ] ; then
  GRINDER_USER="www-data"
else
  echo "Running Grinder as the '$(id -u -n)' user"
  GRINDER_USER="$(id -u -n)"
fi

if grep -Fxq "agent" /etc/grinder/type; then
  if [ ! -f /etc/grinder/console.instance ]; then
    echo "System not configured with an EC2 console instance"
    exit 1
  fi
  GRINDER_CONSOLE_HOST=`sudo -u ${GRINDER_USER} aws ec2 describe-instances --filters Name=instance-id,Values=$(cat /etc/grinder/console.instance) | grep INSTANCES | cut -f 12`
  GRINDER_EXE="Grinder"
  GRINDER_HOST_CONFIG="grinder.consoleHost"
  # Cf. http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html
  GRINDER_AGENT_IP=`curl -s http://169.254.169.254/latest/meta-data/local-ipv4`
elif grep -Fxq "console" /etc/grinder/type; then
  # Cf. http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html
  GRINDER_CONSOLE_HOST=`curl -s http://169.254.169.254/latest/meta-data/local-hostname`

  # Make sure we're responding to our assigned EC2 public address before continuing
  for i in {1..300}; do
    if [ `ping -c 1 ${GRINDER_CONSOLE_HOST} | grep -c '1 received'` == "1" ]; then
      break
    fi
  done

  GRINDER_EXE="Console"
  GRINDER_OPTS="-headless"
  GRINDER_HOST_CONFIG="grinder.console.httpHost"
else
  echo "System not configured with a Grinder type: /etc/grinder/type"
  exit 1
fi

GRINDER_START_CMD="java -Djava.net.preferIPv4Stack=true -D${GRINDER_HOST_CONFIG}=${GRINDER_CONSOLE_HOST} -classpath '/opt/grinder/lib/*' net.grinder.${GRINDER_EXE} ${GRINDER_OPTS}"
GRINDER_WRAPPER_CMD="sudo -u ${GRINDER_USER} -s /bin/bash -c "

case $1 in
start)
  if [ -f $GRINDER_PIDFILE ]; then
    echo "Grinder is already running"
  else
    started=false
    cd $GRINDER_DATA_DIR
    if grep -Fxq "agent" /etc/grinder/type; then
      # Add this agent's security group permissions
      sudo -u ${GRINDER_USER} aws ec2 authorize-security-group-ingress --group-id `cat /etc/grinder/ec2.sgid` --protocol tcp --port 6372 --cidr ${GRINDER_AGENT_IP}/32
    fi
    nohup $GRINDER_WRAPPER_CMD "$GRINDER_START_CMD" > $GRINDER_LOGFILE 2>&1 &
    pid=$!
    echo $pid > $GRINDER_PIDFILE

    # We remove one line in the below because it contains `ps` labels
    while [ `ps -p$pid -o pid | sed "1 d" | wc -l` != 0 ];
    do
      if grep -q "SelectChannelConnector" $GRINDER_LOGFILE; then
        started=true
        break
      fi
      sleep 1
    done

    if [ $started == true ]; then
      echo "Grinder successfully started"
    else
      wait $pid

      if [[ $? != 0 ]]; then
        echo "Failed to start Grinder"
        echo "  Consult the log for more details: $GRINDER_LOGFILE"
      fi
    fi
  fi
  ;;
stop)
  if [ -f $GRINDER_PIDFILE ]; then
    sudo -u $GRINDER_USER pkill -TERM -P `cat $GRINDER_PIDFILE`
    rm -f $GRINDER_PIDFILE
    if grep -Fxq "agent" /etc/grinder/type; then
      # Remove this agent's security group permissions
      sudo -u ${GRINDER_USER} aws ec2 revoke-security-group-ingress --group-id `cat /etc/grinder/ec2.sgid` --protocol tcp --port 6372 --cidr ${GRINDER_AGENT_IP}/32
    fi
    echo "Grinder successfully stopped"
  else
    echo "Grinder is not running"
  fi
  ;;
restart)
  $0 stop
  $0 start
  ;;
status)
  if [ -f $GRINDER_PIDFILE ]; then
    echo "Grinder running"
  else
    echo "Grinder stopped"
  fi
  ;;
*)
  echo "Usage: $0 {start|stop|restart|status}"
  exit 3
  ;;
esac
