#!/usr/bin/sh


#__author__ = 'anildalli'

# AWS_ROLE
#arn:aws:iam::665975628511:role/subscriptions.psedev.automation.jenkins-worker
#arn:aws:iam::384335117118:role/subscriptions.pseprod.automation.jenkins-worker
#arn:aws:iam::742442504506:role/subscriptions.obi-core.aws.dev.automation.jenkins-worker
#arn:aws:iam::308363121193:role/subscriptions.obi-fe.aws.dev.automation.jenkins-worker
#arn:aws:iam::915970820886:role/subscriptions.obi-db.aws.dev.automation.jenkins-worker
#arn:aws:iam::070623800947:role/subscriptions.obi-batch.aws.dev.automation.jenkins-worker
#arn:aws:iam::864643059465:role/subscriptions.dw.aws.dev.automation.jenkins-worker
#arn:aws:iam::349874332661:role/subscriptions.scs.aws.dev.automation.jenkins-worker
#arn:aws:iam::440689293555:role/subscriptions.obi-reports.aws.dev.automation.jenkins-worker
#arn:aws:iam::723694362115:role/subscriptions.obi-core.aws.prod.automation.jenkins-worker
#arn:aws:iam::625735167202:role/subscriptions.obi-fe.aws.prod.automation.jenkins-worker
#arn:aws:iam::463676893277:role/subscriptions.obi-db.aws.prod.automation.jenkins-worker
#arn:aws:iam::754971227468:role/subscriptions.obi-batch.aws.prod.automation.jenkins-worker
#arn:aws:iam::673664509050:role/subscriptions.obi-black.aws.prod.automation.jenkins-worker
#arn:aws:iam::580173953382:role/subscriptions.billingops.automation.jenkins-worker
#arn:aws:iam::759254870277:role/subscriptions.scs.aws.prod.automation.jenkins-worker
#arn:aws:iam::223159632293:role/subscriptions.dw.aws.prod.automation.jenkins-worker


#set -xue pipefail
set +x

# update variable PRJ_HOME in new environment
#
PRJ_HOME="."; export PRJ_HOME
mkdir -p ${PRJ_HOME}/output ${PRJ_HOME}/tmp
ALARM_OFILE=$( echo "${PRJ_HOME}/output/Open_Public_Facing_End_Points.csv" )


# remove the file if exists
#
rm -f ${ALARM_OFILE}	2>/dev/null


# read parameters from jenkins for allowed elbs (ALLOWED_ELBS) and ec2s (ALLOWED_EC2S)
#
elbsAllowed=$( echo ${ALLOWED_ELBS} | sed "s/ [*]/ /g" | sed "s/ /','/g" | sed "s/^/['/g" | sed "s/$/']/g" ); export elbsAllowed
ec2sAllowed=$( echo ${ALLOWED_EC2S} | sed "s/ [*]/ /g" | sed "s/ /','/g" | sed "s/^/['/g" | sed "s/$/']/g" ); export ec2sAllowed

echo "elbsAllowed = ${elbsAllowed}"
echo "ec2sAllowed = ${ec2sAllowed}"

for curr_aws_role in ${AWS_ROLE}; do

  curr_aws_acct=$( echo ${curr_aws_role} | awk -F":" '{print $5}' )
  
  unset AWS_ACCESS_KEY_ID
  unset AWS_SECRET_ACCESS_KEY
  unset AWS_SECURITY_TOKEN
  
  #set +x
  aws sts assume-role --region us-east-1 --role-arn ${curr_aws_role} --role-session-name jenkins | \
      grep -w 'AccessKeyId\|SecretAccessKey\|SessionToken' | \
      sed 's/\"//g;s/\,//;s/ //g' > awscre-${curr_aws_acct} ;\
      export AWS_ACCESS_KEY_ID=$( grep AccessKeyId  awscre-${curr_aws_acct} | awk -F':' '{print $2}' );\
      export AWS_SECRET_ACCESS_KEY=$( grep SecretAccessKey awscre-${curr_aws_acct} | awk -F':' '{print $2}' );\
      export AWS_SECURITY_TOKEN=$( grep SessionToken awscre-${curr_aws_acct} | awk -F':' '{print $2}' );\
  #set -x
  
  if [ ! -z ${AWS_ACCESS_KEY_ID} ]; then
      python3 ${PRJ_HOME}/automations/scanOpenEndpoints.waf.py
  else
  	  echo "ERROR: Not running python script"
  fi
  
  rm -f awscre-${curr_aws_acct} 2>/dev/null
  
  sleep 2

done


# if the list has open public end points then the job fails to trigger OpsGenie alert via post build actions
if [ -s ${ALARM_OFILE} ]; then
	echo "ERROR: We have $( cat ${ALARM_OFILE} | wc -l ) open public end points to alarm"
    exit 1
else
	echo "INFO: nothing to alarm"
fi
    
    
set -x
