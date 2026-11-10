#!/usr/bin/sh 

set +x

#__author__ = 'anildalli'


# variables
prjHome=$(pwd); export prjHome
prjOut=${prjHome}/output; export prjOut
currentDt=$( date '+%Y-%m-%d' )
jenkinsIPaddress=$( hostname -I | awk '{print $1}' )

mkdir -p ${prjOut}
rm -f ${prjOut}/report.csv	2>/dev/null

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
    sed 's/\"//g;s/\,//;s/ //g' > awscre-${currentAWSAccount};\

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

		ec2Instances=$( aws --region ${awsRegion} ec2 describe-instances --query 'Reservations[*].Instances[*].InstanceId' --output text )
		ec2Instances_array=(${ec2Instances})
		echo "Count : ec2s              : ${#ec2Instances_array[@]}"

		ec2InstancesKeyName=$( aws --region ${awsRegion} ec2 describe-instances --query 'Reservations[*].Instances[?KeyName!=`null`].[InstanceId,KeyName]' --output text | sed "s/	/,/g" )
		ec2InstancesKeyName_array=(${ec2InstancesKeyName})
		echo "Count : ec2s with KeyName : ${#ec2InstancesKeyName_array[@]}"

		for x in ${ec2InstancesKeyName_array[@]}; do
			ec2InstanceId=$( echo ${x} | awk -F',' '{print $1}' )
			ec2KeyName=$( echo ${x} | awk -F',' '{print $2}' )
			ec2InstanceName=$( aws --region ${awsRegion} ec2 describe-instances --instance-ids ${ec2InstanceId} --query 'Reservations[*].Instances[*].Tags[?Key==`Name`].Value' --output text )

			echo "${currentAWSAccount},${currentAWSAccountAlias},${awsRegion},${ec2InstanceId},${ec2InstanceName},${ec2KeyName}"	>>${prjOut}/report.csv
		done

	else
		echo "ERROR: AssumeRole operation"
	fi
  
	rm -f awscre-${currentAWSAccount} 2>/dev/null
done
# end of loop for AWS Roles
done
# end of loop for AWs Regions


# Create HTML report
echo "<html>
<h3>Unused SSK Keys - ${currentDt}</h3>
<body>
<table border="1">
<tr>
<th bgcolor="lightblue">AWS Account</th>
<th bgcolor="lightblue">AWS Account Name</th>
<th bgcolor="lightblue">Region</th>
<th bgcolor="lightblue">Instance Id</th>
<th bgcolor="lightblue">Instance Name</th>
<th bgcolor="lightblue">KeyName</th>
<th bgcolor="lightblue">Comment</th>
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
        if [ $( echo ${SSH_KEYNAMES_EXCLUDE_LIST} | egrep "${col6}" | wc -l ) -ne 0 ]; then
        	col7="Ignore: Needed (its part of exlude list)"
            col7_col="green"
        else
        	col7="Review"
            col7_col="red"
        fi

		echo "<tr style=\"color: ${col6_col};\">
		<td>${col1}</td>
		<td>${col2}</td>
		<td>${col3}</td>
		<td>${col4}</td>
        <td>${col4}</td>
		<td>${col5}</td>
        <td>${col7}</td>
		</tr>"	>>${prjOut}/report.html
	done
else
	echo "<tr>Report NA</tr>"
fi
echo "</table></body></html>"	>>${prjOut}/report.html

set -x


