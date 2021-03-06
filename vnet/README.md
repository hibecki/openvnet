# OpenVNet

OpenVNet is a network level hypervisor. It allows you to create virtual L2 networks on top of a physical L3 network.

## Installation

### Dependencies

This guide assumes you have a server running Centos 6.4.

Install the dependencies for making OpenVNet's ruby binary.

    yum install gcc make zlib-devel openssl-devel zeromq-devel

Install the dependencies for installing the ruby gems

    yum install g++ mysql-devel

OpenVNet's nodes communicate through DCell and use redis for DCell's registry. To install redis, we need to add the epel repository.

    yum install wget
    wget http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
    wget http://rpms.famillecollet.com/enterprise/remi-release-6.rpm
    rpm -Uvh remi-release-6*.rpm epel-release-6*.rpm
    yum install redis

Finally install the mysql server

    yum install mysql-server

### OpenVNet manual installation

Create the OpenVNet directory and clone the source from git into it.

    mkdir /opt/axsh/
    cd /opt/axsh
    git clone git@github.com:axsh/openvnet.git

As was mentioned above, OpenVNet uses its own ruby binary. Build it.

    cd /opt/axsh/openvnet/deployment/rubybuild
    ./build_ruby.sh

Add the ruby we built now to your PATH so we can install OpenVNet's gems with it.

    PATH=/opt/axsh/openvnet/ruby/bin:$PATH


We will use bundler to install OpenVNet's gem libraries. First create a config file to separate them from other Ruby programs.

    mkdir /opt/axsh/openvnet/vnet/.bundle

Create the file "/opt/axsh/openvnet/vnet/.bundle/config" with the following contents

    ---
    BUNDLE_PATH: vendor/bundle
    BUNDLE_DISABLE_SHARED_GEMS: '1'

Now use bundler to install the gems

    cd /opt/axsh/openvnet/vnet
    gem install bundler
    bundle install

Prepare the database

    service mysqld start
    mysql -u root
    create database vnet;
    exit
    
    cd /opt/axsh/openvnet/vnet
    bundle exec rake db:init

Start redis

    service redis start

Copy the upstart scripts into their proper directories

    cp /opt/axsh/openvnet/deployment/conf_files/etc/init/* /etc/init
    cp /opt/axsh/openvnet/deployment/conf_files/etc/default/* /etc/default

Start the OpenVNet services

    start vnet-vnmgr
    start vnet-vna
    start vnet-webapi

OpenVNet writes its logs in the /var/log/openvnet directory. If there's a problem starting any of the services, you can find its log files there.

## License
Copyright (c) Axsh Co.
Components are included distribution under LGPL 3.0
