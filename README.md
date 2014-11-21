# Packer AWS Grinder [![Build Status](https://travis-ci.org/ksclarke/packer-aws-grinder.png?branch=master)](https://travis-ci.org/ksclarke/packer-aws-grinder)

A Packer.io build for Grinder.  [Packer.io](http://www.packer.io/) is a tool for creating identical machine images for multiple platforms from a single source configuration.  It supports build products for Amazon EC2, Digital Ocean, Docker, VirtualBox, VMWare, and others.  [Grinder](http://grinder.sourceforge.net/) is load testing framework that makes it easy to run a distributed test using many load injector machines.

For this project, however, only the AWS EC2 builder is used in the Packer.io configuration.  Support for the other Packer.io builders is not planned.

## Introduction

This project uses Packer.io and a couple of Bash scripts to build and start up Grinder in the AWS cloud. The [build.sh](https://github.com/ksclarke/packer-aws-grinder/blob/master/build.sh) script creates AMIs for the Grinder console and agents.  The included, but optional, [start.sh](https://github.com/ksclarke/packer-aws-grinder/blob/master/start.sh) script starts the Grinder cloud and prepares it to receive your tests. Likewise, the [stop.sh](https://github.com/ksclarke/packer-aws-grinder/blob/master/stop.sh) script brings down your AWS Grinder cloud.

_Make sure to read the warnings about the start and stop scripts in the Deployment section below._

## Prerequisites

You should install these prerequisites before running any of the packer-aws-grinder scripts.

* [Packer.io](https://packer.io/intro/getting-started/setup.html)
* [AWS CLI](http://aws.amazon.com/cli/)
* Basic System tools (e.g., echo, openssl, awk, tail, tr, tee, bash)
* [strip-json-comments](https://github.com/sindresorhus/strip-json-comments) (Optional: Only needed if you plan to edit the Packer.io script)

## Configuration

Before you run the build script, you'll need to configure a few important variables. The packer build uses three configuration files (vars.json, agent-vars.json, and console-vars.json).

The `vars/vars.json` file contains the generic configurations (like AWS access key, AWS security group, AWS region, etc.) The `vars/console-vars.json` and `vars/agent-vars.json` files allow you to configure the Grinder console and agents differently (for instance, using different source AMIs, AWS instance types, etc.)

  To get you started, the project has an `vars/example-vars.json` file which can be copied to `vars/vars.json` and then edited.  The same is true for `vars/example-agent-vars.json` (to be copied to `vars/agent-vars.json`) and `vars/example-console-vars.json` (to be copied to `vars/console-vars.json`). The build script will then inject these variables into the build, when appropriate.

_Note: When running the build script, any variable in the project's vars files that ends with `_password` will get an automatically generated value. To have the build script regenerate the `_password` values with a new build, delete the `.passwords` file before re-running the build script. You can also just skip this automated step by providing your own passwords in those files._

### General AWS Grinder Variables

General variables are those that are consistent across the Grinder console and agent machines.

<dl>
  <dt>aws_access_key</dt>
  <dd>A valid AWS_ACCESS_KEY that will be used to interact with Amazon Web Services (AWS).</dd>
  <dt>aws_secret_key</dt>
  <dd>The AWS_SECRET_KEY that corresponds to the supplied AWS_ACCESS_KEY.</dd>
  <dt>aws_security_group_id</dt>
  <dd>A pre-configured AWS Security Group ID (not Name) that will allow SSH access to the EC2 instance. It should also allow access to ports 6372 and 6373. Access can be restricted to the machine from which you will submit the tests.  Access for the Grinder agents is dynamically granted (and revoked) as they are spun up (and shutdown).</dd>
  <dt>aws_region</dt>
  <dd>The AWS region to use. For instance: <span style="font-weight: bold">us-east-1</span> or <span style="font-weight: bold">us-west-2</span>.</dd>
  <dt>packer_build_name</dt>
  <dd>A name that will distinguish your build products from someone else's. It can be a simple string like `Fedora` or `UCLA`.</dd>
</dl>

### AWS Grinder Variables for Console and Agent Var Files

The `agent-vars.json` and `console-vars.json` files have the same set of variables, but are split into two files because one might want different types of AWS instances for the console and agents.

<dl>
  <dt>aws_instance_type</dt>
  <dd>The AWS instance type to use. For instance: <span style="font-weight: bold">t2.medium</span> or <span style="font-weight: bold">m3.medium</span>.</dd>
  <dt>aws_virtualization_type</dt>
  <dd>The AWS virtualization type to use. For instance: <span style="font-weight: bold">hvm</span> or <span style="font-weight: bold">pv</span>.</dd>
  <dt>aws_source_ami</dt>
  <dd>The source AMI to use as a base. Note that the source AMI, virtualization type, and instance type must be <a href="http://aws.amazon.com/amazon-linux-ami/instance-type-matrix/">compatible</a>. If you use a different AMI from the default, make sure it's an Ubuntu image (as that's what the Packer.io build expects).</dd>
</dl>

## Running

To run the packer-aws-grinder build (creating the Grinder AMIs and Console instance), type the following (from within the project directory):

    ./build.sh

_Note: To have the build script use the packer-aws-grinder.json file, you'll need to have [strip-json-comments](https://github.com/sindresorhus/strip-json-comments) installed.  If you don't have that installed, the build script will use the pre-generated aws-grinder.json file. Any changes to the build script meant to persist between builds should be made to the packer-aws-grinder.json file._

## Deployment

To deploy the Grinder machines to the AWS cloud, type:

    ./start.sh <NUMBER_OF_AGENTS>

This will bring up one console and the specified number of agents. So, for instance, one would type `./start.sh 5` to start one console and five agents. The agents will be automatically connected to the console. Grinder tests can then be sent to the console and they will be distributed to the attached agents.

To bring down the Grinder cloud, type:

    ./stop.sh

This will stop the console and agents, keeping both around to be run later.  If you want to actually get rid of the Grinder Agent instances, tell the `stop.sh` script that you want to terminate them by typing:

    ./stop.sh terminate

This will terminate the agent instances, but not the console instance. To do a complete clean (removing the agent instances, the console instance, and all the generated EC2 AMIs (and their snapshots)), type:

    ./stop.sh clean

You will of course, after that, then have to run the `./build.sh` script again to be able to run the `start.sh` and `stop.sh` scripts.

_**Warning:** Running Grinder in the AWS cloud costs money.  The start and stop scripts are provided as a convenience, but you should confirm that they've actually worked.  I'm not responsible for any hours you incur through use of the AWS cloud. **If you don't agree to that, don't use the supplied start and stop scripts**. As an alternative to the provided scripts, you can bring up the console and agents through AWS' Web interface. The agents will automatically connect to console as long as they're brought up after the console is fully functional._

## License

[Apache Software License, version 2.0](LICENSE)

## Contact

If you have questions about [packer-aws-grinder](http://github.com/ksclarke/packer-aws-grinder) feel free to ask them on the FreeLibrary Projects [mailing list](https://groups.google.com/forum/#!forum/freelibrary-projects); or, if you encounter a problem, please feel free to [open an issue](https://github.com/ksclarke/packer-aws-grinder/issues "GitHub Issue Queue") in the project's issue queue.
