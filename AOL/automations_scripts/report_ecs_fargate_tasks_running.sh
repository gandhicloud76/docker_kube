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

		ecs_clusters=$( aws --region ${awsRegion} ecs list-clusters --query 'clusterArns' --output text )
		ecs_clusters_array=(${ecs_clusters})
		if [ ${#ecs_clusters_array[@]} -ne 0 ]; then
			for cluster_name in ${ecs_clusters_array[@]}; do
				ecs_services=$( aws --region ${awsRegion} ecs list-services --cluster ${cluster_name} --query 'serviceArns' --output text )
				ecs_services_array=(${ecs_services})
				if [ ${#ecs_services_array[@]} -ne 0 ]; then
					for service_name in ${ecs_services_array[@]}; do
						runningTasks_ecs=$( aws --region ${awsRegion} ecs describe-services --cluster ${cluster_name} --services ${service_name} | jq -r '.services[].runningCount' )
						cluster_name_fmt=$( echo ${cluster_name} | awk -F'/' '{print $NF}' )
                        service_name_fmt=$( echo ${service_name} | awk -F'/' '{print $NF}' )
                        echo "${currentAWSAccount},${currentAWSAccountAlias},${cluster_name_fmt},${service_name_fmt},${runningTasks_ecs}"
                        echo "${currentAWSAccount},${currentAWSAccountAlias},${cluster_name_fmt},${service_name_fmt},${runningTasks_ecs}"   >>${prjOut}/report.csv
					done
				fi
			done
		fi
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
<h3>Number of Running ECS Fargate Tasks - ${currentDt}</h3>
<body>
<table border="1">
<tr>
<th bgcolor="lightblue">AWS Account</th>
<th bgcolor="lightblue">AWS Account Name</th>
<th bgcolor="lightblue">Cluster Name</th>
<th bgcolor="lightblue">Service Name</th>
<th bgcolor="lightblue">Running Tasks</th>
</tr>"	>${prjOut}/report.html

if [ -s ${prjOut}/report.csv ]; then
	cat ${prjOut}/report.csv | while read x
	do
		col1=$( echo $x | awk -F"," '{print $1}' )
		col2=$( echo $x | awk -F"," '{print $2}' )
		col3=$( echo $x | awk -F"," '{print $3}' )
		col4=$( echo $x | awk -F"," '{print $4}' )
		col5=$( echo $x | awk -F"," '{print $5}' )

		echo "<tr>
		<td>${col1}</td>
		<td>${col2}</td>
		<td>${col3}</td>
		<td>${col4}</td>
		<td>${col5}</td>
		</tr>"	>>${prjOut}/report.html
	done
else
	echo "<tr>Report NA</tr>"
fi
echo "</table></body></html>"	>>${prjOut}/report.html

set -x

