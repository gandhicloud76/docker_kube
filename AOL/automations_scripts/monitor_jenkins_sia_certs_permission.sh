#!/bin/bash

rc=0

### for legacy jenkins
ls -l  /var/lib/sia/certs/obi.dev.legacy-jenkins.cert.pem
if [ $( find /var/lib/sia/certs/ -type f -user root -name obi.dev.legacy-jenkins.cert.pem |wc -l ) -eq 1 ]; then
	echo "file /var/lib/sia/certs/obi.dev.legacy-jenkins.cert.pem owned by root"
    sudo /usr/sbin/siad -cmd rotate
    ls -l  /var/lib/sia/certs/obi.dev.legacy-jenkins.cert.pem
    rc=1
fi


### for etldv 
ssh 10.195.137.217 "ls -l  /var/lib/sia/certs/subscriptions.obi-core.aws.dev.etl5.cert.pem"
if [ $( ssh 10.195.137.217 "find /var/lib/sia/certs/ -type f -user root -name subscriptions.obi-core.aws.dev.etl5.cert.pem" |wc -l ) -eq 1 ]; then
	echo "file /var/lib/sia/certs/subscriptions.obi-core.aws.dev.etl5.cert.pem owned by root"
    ssh 10.195.137.217 "sudo /usr/sbin/siad -cmd rotate"
    ssh 10.195.137.217 "ls -l  /var/lib/sia/certs/subscriptions.obi-core.aws.dev.etl5.cert.pem"
    rc=1
fi


### for etlqa
ssh 10.195.138.30 "ls -l  /var/lib/sia/certs/subscriptions.obi-core.aws.dev.etl6.cert.pem"
if [ $( ssh 10.195.138.30 "find /var/lib/sia/certs/ -type f -user root -name subscriptions.obi-core.aws.dev.etl6.cert.pem" |wc -l ) -eq 1 ]; then
	echo "file /var/lib/sia/certs/subscriptions.obi-core.aws.dev.etl6.cert.pem owned by root"
    ssh 10.195.138.30 "sudo /usr/sbin/siad -cmd rotate"
    ssh 10.195.138.30 "ls -l  /var/lib/sia/certs/subscriptions.obi-core.aws.dev.etl6.cert.pem"
    rc=1
fi

if [ ${rc} -eq 1 ]; then
	exit 1
fi




