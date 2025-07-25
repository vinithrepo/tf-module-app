#!/usr/bin/bash

yum install ansible python3.12-pip.noarch -y   &>>/opt/userdata.log  #you can use here v-3.12 as well

pip3.12 install botocore boto3 &>>/opt/userdata.log
ansible-pull -i localhost, -U https://github.com/vinithrepo/roboshop-ansible.git main.yml -e component=${component} -e env=${env} &>>/opt/userdata.log


