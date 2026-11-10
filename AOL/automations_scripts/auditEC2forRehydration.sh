#!/usr/bin/sh 

set +x

#__author__ = 'anildalli'


# variables
prjHome=$(pwd); export prjHome
prjOut=${prjHome}/output; export prjOut
currentDt=$( date '+%Y-%m-%d' )
jenkinsIPaddress=$( hostname -I | awk '{print $1}' )

mkdir -p ${prjOut}
rm -f ${prjOut}/report.csv ${prjOut}/report.tmp.csv	2>/dev/null

echo "# project-home      : ${prjHome}"
echo "# role-session-name : ${jenkinsIPaddress}"
echo "# current-timestamp : $( date '+%Y-%m-%d %H:%M')"

for awsRegion in ${AWS_REGION}; do

echo "# awsRegion         : ${awsRegion}"

for currentAWSRole in ${AWS_ROLE}; do

	currentAWSAccount=$( echo ${currentAWSRole} | awk -F":" '{print $5}' )

	unset AWS_ACCESS_KEY_ID
	unset AWS_SECRET_ACCESS_KEY
	unset AWS_SECURITY_TOKEN
  
	aws sts assume-role --region ${awsRegion} --role-arn ${currentAWSRole} --role-session-name ${jenkinsIPaddress} 2>awscre-${currentAWSAccount}.err | \
	grep -w 'AccessKeyId\|SecretAccessKey\|SessionToken' | \
	sed 's/\"//g;s/\,//;s/ //g' > awscre-${currentAWSAccount} ;\

  if [[ -s awscre-${currentAWSAccount}.err ]]; then
    if [[ $( cat awscre-${currentAWSAccount}.err | egrep "RegionDisabledException" | wc -l ) -eq 1 ]]; then
      echo "################################################################"
      echo "AWS Account: ${currentAWSAccount}"
      echo "################################################################"
      echo "Warning: RegionDisabledException, skip"
      cat awscre-${currentAWSAccount}.err
      continue
    fi
  fi

	export AWS_ACCESS_KEY_ID=$( grep AccessKeyId awscre-${currentAWSAccount} | awk -F':' '{print $2}' );\
	export AWS_SECRET_ACCESS_KEY=$( grep SecretAccessKey awscre-${currentAWSAccount} | awk -F':' '{print $2}' );\
	export AWS_SECURITY_TOKEN=$( grep SessionToken awscre-${currentAWSAccount} | awk -F':' '{print $2}' );\

	if [ ! -z ${AWS_ACCESS_KEY_ID} ]; then  

		#get account alias
		currentAWSAccountAlias=$( aws --region ${awsRegion} iam list-account-aliases --output text | awk '{print $2}' )

		echo "################################################################"
		echo "AWS Account: ${currentAWSAccount} - ${currentAWSAccountAlias}"
		echo "################################################################"
		
		echo "${currentAWSAccount}(${currentAWSAccountAlias})"

		ec2Instances=$( aws --region ${awsRegion} ec2 describe-instances --query 'Reservations[*].Instances[*].InstanceId' --output text )
                ec2Instances_array=(${ec2Instances})
                echo "Count : ec2s              : ${#ec2Instances_array[@]}"

                for ec2InstanceId in ${ec2Instances_array[@]}; do
                        ec2InstanceName=$( aws --region ${awsRegion} ec2 describe-instances --instance-ids ${ec2InstanceId} --query 'Reservations[*].Instances[*].Tags[?Key==`Name`].Value' --output text )
                        ec2InstanceState=$( aws --region ${awsRegion} ec2 describe-instances --instance-ids ${ec2InstanceId} --query 'Reservations[*].Instances[*].State[].Name' --output text )
			if [ ${ec2InstanceState} == "terminated" ]; then 
				echo "     ${ec2InstanceId} (${ec2InstanceName}) is ${ec2InstanceState} ---- skip (do nothing)"
				continue; 
			fi
			ec2EbsLaunchTime=$( aws --region ${awsRegion} ec2 describe-instances --instance-ids ${ec2InstanceId} --query 'Reservations[*].Instances[*].BlockDeviceMappings[0].Ebs[].AttachTime' --output text | awk -F'T' '{print $1}' )
			if [ -z ${ec2EbsLaunchTime} ]; then ec2EbsLaunchTime='1970-01-01'; fi

			expiryDt=$( date -d"+90 days ${ec2EbsLaunchTime}" '+%Y-%m-%d' )
			rehydrationDt=$( date -d"-10 days ${expiryDt}" '+%Y-%m-%d' )

			rehydrationFlag=0
			if [ $( echo ${rehydrationDt} | sed "s/-//g" ) -le $( echo ${currentDt} | sed "s/-//g" ) ]; then
				rehydrationFlag=1
			else
				rehydrationFlag=0
			fi
		
			if [ ${rehydrationFlag} -eq 1 ]; then
				statusInfo="ActionReqd: Due for Rehydration"
			else
				statusInfo=""
			fi
			echo "     ${ec2InstanceId} (${ec2InstanceName}) is ${ec2InstanceState} ---- created on ${ec2EbsLaunchTime} rehydration due by ${rehydrationDt}"
                        echo "${currentAWSAccount},${currentAWSAccountAlias},${ec2InstanceId},${ec2InstanceName},${ec2InstanceState},${ec2EbsLaunchTime},${expiryDt},${rehydrationDt},${statusInfo}" >>${prjOut}/report.tmp.csv
                done
	else
		echo "ERROR: AssumeRole operation"
	fi
  
	rm -f awscre-${currentAWSAccount} 2>/dev/null
done
# end of loop for AWS Roles
done
# end of loop for AWs Regions
cat ${prjOut}/report.tmp.csv | sort -t',' -k6 >${prjOut}/report.csv


# Create HTML report
echo "<html>
<h3>EC2 Rehydration Status Report - ${currentDt}</h3>
<body>
<table border="1">
<tr>
<th bgcolor="lightblue">AWS Account</th>
<th bgcolor="lightblue">AWS Account Name</th>
<th bgcolor="lightblue">Instance Id</th>
<th bgcolor="lightblue">Name</th>
<th bgcolor="lightblue">State</th>
<th bgcolor="lightblue">Creation Date</th>
<th bgcolor="lightblue">Rehydration Hard Due Date</th>
<th bgcolor="lightblue">Rehydration Soft Due Date</th>
<th bgcolor="lightblue">Status</th>
</tr>"	>${prjOut}/report.html

if [ -s ${prjOut}/report.csv ]; then
        cat ${prjOut}/report.csv | while read x
        do
                col1=$( echo $x | awk -F"," '{print $1}' )
                col2=$( echo $x | awk -F"," '{print $2}' )
                col3=$( echo $x | awk -F"," '{print $3}' )
                col4=$( echo $x | awk -F"," '{print $4}' )
                col5=$( echo $x | awk -F"," '{print $5}' )
                col6=$( echo $x | awk -F"," '{print $6}' )
                col7=$( echo $x | awk -F"," '{print $7}' )
                col8=$( echo $x | awk -F"," '{print $8}' )
                col9=$( echo $x | awk -F"," '{print $9}' )
                if [ $( echo "${col9}" | egrep "ActionReqd" | wc -l ) -eq 0 ]; then col9_col=""; else col9_col="red"; fi

                echo "<tr style=\"color: ${col9_col};\">
                <td>${col1}</td>
                <td>${col2}</td>
                <td>${col3}</td>
                <td>${col4}</td>
                <td>${col5}</td>
                <td>${col6}</td>
                <td>${col7}</td>
                <td>${col8}</td>
                <td>${col9}</td>
                </tr>"  >>${prjOut}/report.html
        done
else
        echo "<tr>Report NA - Pls check</tr>"	>>${prjOut}/report.html
fi
echo "</table></body></html>"	>>${prjOut}/report.html

if [ $( cat ${prjOut}/report.csv | egrep "ActionReqd" | wc -l ) -ge 1 ]; then
        echo "***** ERROR *****: Send Ops Genie alarm to obi_prod_alerts slack alarm in post build actions"
        exit 1
else
        echo "INFO             : All good. Nothing to alarm."
fi

set -x
