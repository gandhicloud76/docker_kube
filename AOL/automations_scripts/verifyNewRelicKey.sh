#!/usr/bin/bash

tmpDir="/tmp"

mkdir -p ${tmpDir}

echo "##### Run awsfed to get all aws account numbers"
echo '0' | awsfed -n | grep Account | sed "s/ //g" | awk -F':' '{print $3","$4}' >${tmpDir}/awsfed.out

cat ${tmpDir}/awsfed.out | egrep "obi|scs|665975628511|384335117118|580173953382" >${tmpDir}/awsfed.out.tmp
#cat ${tmpDir}/awsfed.out | egrep "678186484068|513247337236|services|frontends" >${tmpDir}/awsfed.out.tmp
mv ${tmpDir}/awsfed.out.tmp ${tmpDir}/awsfed.out

echo "##### Run awsfed to login to each distinct aws account"
cat ${tmpDir}/awsfed.out | awk -F',' '{print $1}' | awk -F'(' '{print $1}' | sort -u | while read acctNum
do
  acctName=$( cat ${tmpDir}/awsfed.out | egrep ${acctNum} | awk -F',' '{print $1}' | awk -F'(' '{print $2}' | awk -F')' '{print $1}' | sort -u )
  roleName=$( cat ${tmpDir}/awsfed.out | egrep ${acctNum} | awk -F',' '{print $2}' | head -1 )

  echo ""
  echo ""
  echo ""
  echo "-------------------------------------------------------------------------"
  echo ""

  # login to each distinct aws account
  awsfed --profile=${acctName} --account=${acctNum} --role=${roleName} -n >/dev/null 2>&1
  export AWS_PROFILE=${acctName}

  # get list of aws regions
  aws ec2 describe-regions --region us-east-1 | jq -r '.Regions[].RegionName' | egrep "us-east-1|us-east-2" >${tmpDir}/awsRegions.out
  #aws ec2 describe-regions --region us-east-1 | jq -r '.Regions[].RegionName' | egrep "us-east-1|us-east-2|us-west-2|ap-southeast-1|eu-west-1" >${tmpDir}/awsRegions.out

  for awsRegion in `cat ${tmpDir}/awsRegions.out`
do
    ssmParams=$( aws --profile ${acctName} --region ${awsRegion} ssm describe-parameters | jq -r '.Parameters[].Name' )

    for param in $ssmParams; do
      echo "### ${acctNum} - ${acctName} - ${awsRegion} - Parameter: ${param}"
      aws --profile ${acctName} --region ${awsRegion} ssm get-parameters --with-decryption --names $param --query "Parameters[*].{Name:Name,Value:Value}" | jq -r '.[].Value' | egrep -i "OBI_NEWRELIC_LICENSE_KEY"

    done
      echo "central"
      aws --profile ${acctName} --region ${awsRegion} ssm get-parameters --with-decryption --names /infrastructure/newrelic_key --query "Parameters[*].{Name:Name,Value:Value}"
done

done
