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

echo "#"
echo "#"
echo "#"
echo "#"
echo "#"
echo "#"
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

		#
		# Scan for SGs used for below AWS services:
		# 	EC2 instances
		#	EC2 SG default
		#	EC2 VPC endpoints
		#	ELB and ELBv2
		#	RDS instances
		#	Network Interfaces
		#	Elasticache
		#	ECS
		#	Lambda
		#	Elastic Search
		#

		sg_all_array_uniq=()
		sg_used_array=()
		sg_used_array_uniq=()

		sg_all=$( aws --region ${awsRegion} ec2 describe-security-groups --query 'SecurityGroups[*].[GroupId]'  --output text )
		sg_all_array=(${sg_all})
		echo "Count : sg_all         : ${#sg_all_array[@]}"

		sg_ec2=$( aws --region ${awsRegion} ec2 describe-instances --query 'Reservations[*].Instances[*].SecurityGroups[*].GroupId' --output text )
		sg_ec2_array=(${sg_ec2})
		sg_used_array+=(${sg_ec2})
		echo "Count : sg_ec2         : ${#sg_ec2_array[@]}"

		sg_ec2_default=$( aws --region ${awsRegion} ec2 describe-security-groups --query 'SecurityGroups[?GroupName==`default`].[GroupId]'  --output text )
		sg_ec2_default_array=(${sg_ec2_default})
		sg_used_array+=(${sg_ec2_default})
		echo "Count : sg_ec2_default : ${#sg_ec2_default_array[@]}"

		sg_ec2_vpcep=$( aws --region ${awsRegion} ec2 describe-vpc-endpoints --query 'VpcEndpoints[*].Groups[*].GroupId' --output text )
		sg_ec2_vpcep_array=(${sg_ec2_vpcep})
		sg_used_array+=(${sg_ec2_vpcep})
		echo "Count : sg_ec2_vpcep   : ${#sg_ec2_vpcep_array[@]}"

		sg_elb=$( aws --region ${awsRegion} elb describe-load-balancers --query 'LoadBalancerDescriptions[*].SecurityGroups' --output text )
		sg_elb_array=(${sg_elb})
		sg_used_array+=(${sg_elb})
		echo "Count : sg_elb         : ${#sg_elb_array[@]}"

		sg_elbv2=$( aws --region ${awsRegion} elbv2 describe-load-balancers --query 'LoadBalancers[*].SecurityGroups' --output text )
		sg_elbv2_array=(${sg_elbv2})
		sg_used_array+=(${sg_elbv2})
		echo "Count : sg_elbv2       : ${#sg_elbv2_array[@]}"

		sg_rds=$( aws --region ${awsRegion} rds describe-db-instances --query 'DBInstances[*].VpcSecurityGroups[*].VpcSecurityGroupId' --output text )
		sg_rds_array=(${sg_rds})
		sg_used_array+=(${sg_rds})
		echo "Count : sg_rds         : ${#sg_rds_array[@]}"

		sg_eni=$( aws --region ${awsRegion} ec2 describe-network-interfaces --query 'NetworkInterfaces[*].Groups[*].GroupId' --output text )
		sg_eni_array=(${sg_eni})
		sg_used_array+=(${sg_eni})
		echo "Count : sg_eni         : ${#sg_eni_array[@]}"

		sg_elasticache=$( aws --region ${awsRegion} elasticache describe-cache-clusters --query 'CacheClusters[*].SecurityGroups[*].SecurityGroupId' --output text )
		sg_elasticache_array=(${sg_elasticache})
		sg_used_array+=(${sg_elasticache})
		echo "Count : sg_elasticache : ${#sg_elasticache_array[@]}"

		ecs_clusters=$( aws --region ${awsRegion} ecs list-clusters --query 'clusterArns' --output text )
		ecs_clusters_array=(${ecs_clusters})
		if [ ${#ecs_clusters_array[@]} -ne 0 ]; then
			for cluster_name in ${ecs_clusters_array[@]}; do
				ecs_services=$( aws --region ${awsRegion} ecs list-services --cluster ${cluster_name} --query 'serviceArns' --output text )
				ecs_services_array=(${ecs_services})
				if [ ${#ecs_services_array[@]} -ne 0 ]; then
					for service_name in ${ecs_services_array[@]}; do
						sg_ecs=$( aws --region ${awsRegion} ecs describe-services --cluster ${cluster_name} --services ${service_name} --query 'services[*].networkConfiguration[].awsvpcConfiguration[].securityGroups' --output text )
						sg_ecs_array+=(${sg_ecs})
					done
				fi
			done
		fi
		sg_used_array+=(${sg_ecs})
		echo "Count : sg_ecs         : ${#sg_ecs_array[@]}"

		lambda_func=$( aws --region ${awsRegion} lambda list-functions --query 'Functions[*].FunctionName' --output text )
		lambda_func_array=(${lambda_func})
		if [ ${#lambda_func_array[@]} -ne 0 ]; then
			for func_name in ${lambda_func_array[@]}; do
				sg_lambda=$( aws --region ${awsRegion} lambda get-function --function-name ${func_name} --query 'Configuration.VpcConfig.SecurityGroupIds' --output text )
				sg_lambda_array+=(${sg_lambda})
			done
		fi
		sg_used_array+=(${sg_lambda})
		echo "Count : sg_lambda      : ${#sg_lambda_array[@]}"

		es_domain=$( aws --region ${awsRegion} es list-domain-names --query 'DomainNames[*].DomainName' --output text )
		es_domain_array=(${es_domain})
		if [ ${#es_domain_array[@]} -ne 0 ]; then
			for domain_name in ${es_domain_array[@]}; do
				sg_es=$( aws --region ${awsRegion} es describe-elasticsearch-domain --domain-name ${domain_name} --query 'DomainStatus.VPCOptions.SecurityGroupIds' --output text )
				sg_es_array+=(${sg_es})
			done
		fi
		sg_used_array+=(${sg_es})
		echo "Count : sg_es          : ${#sg_es_array[@]}"

		sg_all_array_uniq=($(echo "${sg_all_array[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ' ))
		sg_used_array_uniq=($(echo "${sg_used_array[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ' ))

		cnt_sg_all=${#sg_all_array[@]}
		cnt_sg_all_uniq=${#sg_all_array_uniq[@]}
		cnt_sg_used=${#sg_used_array[@]}
		cnt_sg_used_uniq=${#sg_used_array_uniq[@]}

		echo "Total SG               : ${#sg_all_array[@]}"
		echo "Total SG (distinct)    : ${#sg_all_array_uniq[@]}"
		echo "Used SG                : ${#sg_used_array[@]}"
		echo "Used SG (distinct)     : ${#sg_used_array_uniq[@]}"
		
		# exclude used SG from all
		for x in ${sg_used_array_uniq[@]}; do
		        sg_all_array_uniq=(${sg_all_array_uniq[@]/$x})
		done
	
		sg_unused_filename="${currentAWSAccount}-unused-sg.${awsRegion}.lst"	
		rm -f ${prjOut}/${sg_unused_filename}	2>/dev/null
		touch ${prjOut}/${sg_unused_filename}
		if [ ${#sg_all_array_uniq[@]} -ne 0 ]; then
			for sg_id in ${sg_all_array_uniq[@]}; do
				sg_name=$( aws --region ${awsRegion} ec2 describe-security-groups --group-ids ${sg_id} --query 'SecurityGroups[*].GroupName' --output text )
				echo "${sg_id}:${sg_name}"
			done >${prjOut}/${sg_unused_filename}
		fi
		echo "Unused SG (distinct)   : ${#sg_all_array_uniq[@]}"
		cnt_sg_unused=${#sg_all_array_uniq[@]}
		
		echo "${currentAWSAccount},${currentAWSAccountAlias},${awsRegion},${cnt_sg_all_uniq},${cnt_sg_used_uniq},${cnt_sg_unused},${sg_unused_filename}"	>>${prjOut}/report.csv
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
<h3>Unused Security Groups - ${currentDt}</h3>
<body>
<table border="1">
<tr>
<th bgcolor="lightblue">AWS Account</th>
<th bgcolor="lightblue">AWS Account Name</th>
<th bgcolor="lightblue">Region</th>
<th bgcolor="lightblue">Total SGs</th>
<th bgcolor="lightblue">In-Use SGs</th>
<th bgcolor="lightblue">Unused SGs</th>
<th bgcolor="lightblue">Unused SGs filename</th>
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
		if [ ${col6} -eq 0 ]; then col6_col=""; else col6_col="red"; fi
		col7=$( echo $x | awk -F"," '{print $7}' )

		echo "<tr>
		<td><font color=${col6_col}>${col1}</font></td>
		<td><font color=${col6_col}>${col2}</font></td>
		<td><font color=${col6_col}>${col3}</font></td>
		<td><font color=${col6_col}>${col4}</font></td>
		<td><font color=${col6_col}>${col5}</font></td>
                <td><font color=${col6_col}>${col6}</font></td>
		<td><font color=${col6_col}>output/${col7}</a></font></td>
		</tr>"	>>${prjOut}/report.html
	done
else
	echo "<tr>Report NA</tr>"
fi
echo "</table></body></html>"	>>${prjOut}/report.html

set -x

