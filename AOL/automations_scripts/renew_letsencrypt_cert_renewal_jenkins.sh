#!/usr/bin/sh


#__author__ = 'anildalli'


#set -xue pipefail
set +x

# update variable PRJ_HOME in new environment
#
PRJ_HOME="."; export PRJ_HOME


# remove the file if exists
#
#rm -f ${PRJ_HOME}/*txt	2>/dev/null


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
      ${PRJ_HOME}/letsencrypt_cert_renew/bin/renew_letsencypt_cert.expect.gitlab.sh
      if [ $? -ne 0 ]; then
      	echo "Error: running expect script"
        exit 1
      fi
  else
  	  echo "ERROR: AWS ACCESS KEY ID is null"
      exit 1
  fi
  
  rm -f awscre-${curr_aws_acct} 2>/dev/null
  
  sleep 2

done
    
    
set -x
