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
		#
		
		auth_listener_arns=$( aws --region ${awsRegion} elbv2 describe-listeners --load-balancer-arn "${AUTH_NLB_ARN}" | jq -r '.Listeners[].ListenerArn' )
        auth_listener_arns_array=(${auth_listener_arns})
        
        if [ ${#auth_listener_arns_array[@]} -ne 0 ]; then
		  for listener_arn in ${auth_listener_arns_array[@]}; do
            listener_port=$( aws --region ${awsRegion} elbv2 describe-listeners --listener-arns ${listener_arn} | jq '.Listeners[].Port' )
            echo "### Auth listener - ${listener_arn} : ${listener_port}"
            if [[ ${listener_port} == 443 ]]; then
              live_listener_arn=${listener_arn}
            elif [[ ${listener_port} == 8998 ]]; then
              paymentech_listener_arn=${listener_arn}
            fi
           done
        fi
        echo ""
        echo "Live Listener      : ${live_listener_arn}"
        echo "Paymentech Listener: ${paymentech_listener_arn}"
        echo ""
        live_target_group_arn=$( aws --region ${awsRegion} elbv2 describe-listeners --listener-arns "${live_listener_arn}" | jq -r '.Listeners[].DefaultActions[].TargetGroupArn' )
        paymentech_target_group_arn=$( aws --region ${awsRegion} elbv2 describe-listeners --listener-arns "${paymentech_listener_arn}" | jq -r '.Listeners[].DefaultActions[].TargetGroupArn' )
        echo ""
        echo "Live Target Group      : ${live_target_group_arn}"
        echo "Paymentech Target Group: ${paymentech_target_group_arn}"
        echo ""
        
        live_targets=$( aws --region ${awsRegion} elbv2 describe-target-health --target-group-arn ${live_target_group_arn} | jq -r '.TargetHealthDescriptions[] | select( "\(.TargetHealth.State)" == "healthy" ) | "\(.Target.Id)"' | sort -n )
        live_targets_array=(${live_targets})
        #TargetHealth
        
        paymentech_targets=$( aws --region ${awsRegion} elbv2 describe-target-health --target-group-arn ${paymentech_target_group_arn} | jq -r '.TargetHealthDescriptions[] | select( "\(.TargetHealth.State)" == "healthy" ) | "\(.Target.Id)"' | sort -n )
        paymentech_targets_array=(${paymentech_targets})
        
        num_targets_live=${#live_targets_array[@]}
        num_targets_paymentech=${#paymentech_targets_array[@]}
        
        echo ""
        echo "Live Targets      : ${num_targets_live}"
        echo "Paymentech Targets: ${num_targets_paymentech}"
        echo ""

        paymentech_unhealthy_targets=$( aws --region ${awsRegion} elbv2 describe-target-health --target-group-arn ${paymentech_target_group_arn} | jq -r '.TargetHealthDescriptions[] | select( "\(.TargetHealth.State)" == "unhealthy" ) | "\(.Target.Id)"' | sort -n )
        paymentech_unhealthy_targets_array=(${paymentech_unhealthy_targets})
        num_targets_paymentech_unhealthy=${#paymentech_unhealthy_targets[@]}

        echo ""
        echo "Paymentech Targets (unhealthy): ${num_targets_paymentech_unhealthy}"
        echo ""

        if [[ ${num_targets_paymentech_unhealthy} -ge 1 ]]; then
           
          num_paymentech_unhealthy_targets=$( echo ${#paymentech_unhealthy_targets_array[@]} -1 | bc )
        
          for num in $( seq 0 ${num_paymentech_unhealthy_targets} ); do
            if [[ $( aws --region ${awsRegion} elbv2 describe-target-health --target-group-arn ${paymentech_target_group_arn} | jq -r '.TargetHealthDescriptions[].TargetHealth.State' ) == "draining" ]]; then
              echo "### Target in Draining state. Skip deregister target."
            else
              echo "### Action: De-Register paymentech target group with IP - ${paymentech_unhealthy_targets_array[${num}]}"
              aws --region ${awsRegion} elbv2 deregister-targets --target-group-arn ${paymentech_target_group_arn} --targets Id=${paymentech_unhealthy_targets_array[${num}]}
              if [[ $? -eq 0 ]]; then
                echo "### Unhealthy target de-registered"
              fi
            fi
          done
        fi
        
        num_targets=$( echo ${#live_targets_array[@]} -1 | bc )
        
        for num in $( seq 0 ${num_targets} ); do
          if [[ ${live_targets_array[${num}]} == ${paymentech_targets_array[${num}]} ]]; then
            echo "### Info: Paymentech already having live target - ${paymentech_targets_array[${num}]}"
            echo "### Do nothing"
          else
            if [[ $( aws --region ${awsRegion} elbv2 describe-target-health --target-group-arn ${paymentech_target_group_arn} | jq -r '.TargetHealthDescriptions[].TargetHealth.State' ) == "initial" ]]; then
              echo "### Target in Initial state. Skip register target."
            else
              echo "### Action: Register live target to paymentech target group with IP - ${live_targets_array[${num}]}"
              aws --region ${awsRegion} elbv2 register-targets --target-group-arn ${paymentech_target_group_arn} --targets Id=${live_targets_array[${num}]}
              if [[ $? -eq 0 ]]; then
                echo "### New target registered"
              fi
            fi
          fi
        done
        
	else
		echo "ERROR: AssumeRole operation"
	fi
  
	rm -f awscre-${currentAWSAccount} 2>/dev/null
done
# end of loop for AWS Roles
done
# end of loop for AWS Regions


