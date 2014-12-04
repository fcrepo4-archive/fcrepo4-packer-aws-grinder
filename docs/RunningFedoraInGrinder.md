## Running Fedora's Grinder Tests

There are different ways to run the Fedora Grinder tests.  This document describes one option, running them against a Grinder cloud created with fcrepo4-packer-aws-grinder.

The first thing you'll want to do is to start the AWS Grinder cloud with the desired number of agents.  To do this (with five agents, for example), type:

    ./start.sh 5

You should get output that looks something like:

    Started Grinder Console (i-99cb7775) at 54.174.175.69
     Started Grinder Agent #1 (i-c5b00c29) at 172.31.10.92
     Started Grinder Agent #2 (i-68b10d84) at 172.31.12.75
     Started Grinder Agent #3 (i-86b10d6a) at 172.31.13.23
     Started Grinder Agent #4 (i-91b20e7d) at 172.31.7.241
     Started Grinder Agent #5 (i-85b20e69) at 172.31.12.156

You can confirm all the agents are properly connected by visiting the console's IP address in your browser.  For instance, visit:

    http://54.174.175.69:6373/agents/status

You should see output like:

    - id: ip-172-31-10-92.ec2.internal:119528060|1417628674248|-1282848967:0
      name: ip-172-31-10-92.ec2.internal
      number: -1
      state: RUNNING
      workers: []
    - id: ip-172-31-12-156.ec2.internal:119528060|1417628909047|1353592767:0
      name: ip-172-31-12-156.ec2.internal
      number: -1
      state: RUNNING
      workers: []
    - id: ip-172-31-12-75.ec2.internal:1010894475|1417628712320|1098448046:0
      name: ip-172-31-12-75.ec2.internal
      number: -1
      state: RUNNING
      workers: []
    - id: ip-172-31-13-23.ec2.internal:1010894475|1417628770135|-1680886484:0
      name: ip-172-31-13-23.ec2.internal
      number: -1
      state: RUNNING
      workers: []
    - id: ip-172-31-7-241.ec2.internal:119528060|1417628836505|-1496178640:0
      name: ip-172-31-7-241.ec2.internal
      number: -1
      state: RUNNING
      workers: []

To see the default properties that are set in the Grinder console, install [jq](https://stedolan.github.io/jq/) and type the following:

    jq . <<< `curl -s http://54.174.175.69:6373/properties`

You don't actually _need_ jq, but if you don't use it you'll probably want to pipe the results through something that will pretty print the JSON output for you.

Next, we'll want to go ahead and install an instance of Fedora in the cloud.  This can be done with the fedora.sh script... to use it, just type:

    ./fedora.sh start

The output from the fedora.sh script should look like:

    Running EC2 Fedora instance "i-587fc3b4" at 54.173.207.150

You can confirm it's up by visiting its RESTful interface:

    http://54.173.207.150:8080/fcrepo/rest
