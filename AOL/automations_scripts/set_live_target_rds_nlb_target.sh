#!/usr/bin/sh 

set +x

#__author__ = 'anildalli'


# variables
prjHome=$(pwd); export prjHome
prjOut=${prjHome}/output; export prjOut
currentDt=$( date '+%Y-%m-%d' )
jenkinsIPaddress=$( hostname -I | awk '{print $1}' )

mkdir -p ${prjOut}
rm -f ${prjOut}/* 2>/dev/null

echo "# project-home      : ${prjHome}"
echo "# role-session-name : ${jenkinsIPaddress}"
echo "# current-timestamp : $( date '+%Y-%m-%d %H:%M')"

for currentAWSRole in ${AWS_ROLE}; do
for awsRegion in ${AWS_REGION}; do

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
    echo "${currentAWSAccount},${currentAWSAccountAlias}" >>${prjOut}/acct_alias.mapping.txt

		echo "################################################################"
		echo "AWS Account: ${currentAWSAccount} - ${currentAWSAccountAlias}"
		echo "################################################################"
    echo "## awsRegion         : ${awsRegion}"

		#
		# Get New Target from RDS DNS endpoint
    new_target_ip=$( dig +short ${RDS_ENDPOINT} )
    if [[ -z ${new_target_ip} ]]; then
      new_target_ip=$( nslookup ${RDS_ENDPOINT} | grep 'Address:' | tail -n 1 | awk '{print $2}' )
    fi
    if [[ -z ${new_target_ip} ]]; then
      echo "### Info: RDS Endpoint is not being resolved"
      exit 1
    fi
    echo "### Info: RDS Endpoint IP : ${new_target_ip}"
		
		listener_arn=$( aws --region ${awsRegion} elbv2 describe-listeners --load-balancer-arn "${RDS_NLB_ARN}" | jq -r '.Listeners[].ListenerArn' )
    listener_port=$( aws --region ${awsRegion} elbv2 describe-listeners --listener-arns ${listener_arn} | jq '.Listeners[].Port' )
    echo "### Info: RDS Listener : ${listener_arn}"
    echo "### Info: RDS Listener Port : ${listener_port}"
    if [[ ${listener_port} != 3306 ]]; then
      echo "### ERROR: RDS Listener - Port expected is 3306"
      exit 1
    fi
    
    target_group_arn=$( aws --region ${awsRegion} elbv2 describe-listeners --listener-arns "${listener_arn}" | jq -r '.Listeners[].DefaultActions[].TargetGroupArn' )
    echo "### Info: RDS Target Group : ${target_group_arn}"
    
    targets=$( aws --region ${awsRegion} elbv2 describe-target-health --target-group-arn ${target_group_arn} | jq -r '.TargetHealthDescriptions[].Target.Id' )
    targets_array=(${targets})
    num_targets=${#targets_array[@]}
    echo "### Info: RDS Targets : ${num_targets}"
    
    NEW_TARGET_PRESENT=0
    NEW_TARGET_PRESENT_MSG="Register new target"

    if [[ ${num_targets} -ge 1 ]]; then
      for current_target_ip in ${targets_array[@]}; do
        if [[ "${new_target_ip}" == "${current_target_ip}" ]]; then
          NEW_TARGET_PRESENT=1
          NEW_TARGET_PRESENT_MSG="Do nothing"
        fi
        target_state=$( aws --region ${awsRegion} elbv2 describe-target-health --target-group-arn ${target_group_arn} | jq -r --arg target_id "${current_target_ip}" '.TargetHealthDescriptions[] | select(.Target.Id == $target_id) | .TargetHealth.State' )
        if [[ ${target_state} == "healthy" ]]; then
          echo "Info: RDS Target : ${current_target_ip} : healthy : Do nothing"
        elif [[ ${target_state} == "draining" ]]; then
          echo "Info: RDS Target : ${current_target_ip} : draining : Do nothing"
        elif [[ ${target_state} == "initial" ]]; then
          echo "Info: RDS Target : ${current_target_ip} : initial : Do nothing"
        elif [[ ${target_state} == "unhealthy" ]]; then
          echo "Info: RDS Target : ${current_target_ip} : unhealthy : De-Register existing target"
          # De-Register
          aws --region ${awsRegion} elbv2 deregister-targets --target-group-arn ${target_group_arn} --targets Id=${current_target_ip}
          if [[ $? -eq 0 ]]; then
            echo "### Info: RDS Target : ${current_target_ip} de-registered"
          fi
        fi
      done
      echo "Info: RDS New Target Present : ${NEW_TARGET_PRESENT} -> yes=1, no=0 : ${NEW_TARGET_PRESENT_MSG}"
      if [[ ${NEW_TARGET_PRESENT} -eq 0 ]]; then
        aws --region ${awsRegion} elbv2 register-targets --target-group-arn ${target_group_arn} --targets Id=${new_target_ip}
        if [[ $? -eq 0 ]]; then
          echo "### Info: RDS Target : ${new_target_ip} registered"
        fi
      fi
    else
      echo "### Info: RDS Targets regsitered to NLB : 0 : Register new target"
      aws --region ${awsRegion} elbv2 register-targets --target-group-arn ${target_group_arn} --targets Id=${new_target_ip}
      if [[ $? -eq 0 ]]; then
        echo "### Info: RDS Target : ${new_target_ip} registered"
      fi
    fi
	else
		echo "ERROR: AssumeRole operation"
	fi
	rm -f awscre-${currentAWSAccount} 2>/dev/null
done # end of loop for AWS Roles
done # end of loop for AWS Regions
