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
		
		vertexo9_listener_arns=$( aws --region ${awsRegion} elbv2 describe-listeners --load-balancer-arn "${VERTEXO9_ALB_ARN}" | jq -r '.Listeners[].ListenerArn' )
        vertexo9_listener_arns_array=(${vertexo9_listener_arns})
        
        if [ ${#vertexo9_listener_arns_array[@]} -ne 0 ]; then
		  for listener_arn in ${vertexo9_listener_arns_array[@]}; do
            listener_port=$( aws --region ${awsRegion} elbv2 describe-listeners --listener-arns ${listener_arn} | jq '.Listeners[].Port' )
            echo "### Auth listener - ${listener_arn} : ${listener_port}"
            if [[ ${listener_port} == 443 ]]; then
              live_listener_arn=${listener_arn}
            elif [[ ${listener_port} == 80 ]]; then
              http_listener_arn=${listener_arn}
            fi
           done
        fi
        echo ""
        echo "Live Listener: ${live_listener_arn}"
        echo "HTTP Listener: ${http_listener_arn}"
        echo ""
        live_target_group_arn=$( aws --region ${awsRegion} elbv2 describe-listeners --listener-arns "${live_listener_arn}" | jq -r '.Listeners[].DefaultActions[].TargetGroupArn' )
        http_target_group_arn=$( aws --region ${awsRegion} elbv2 describe-listeners --listener-arns "${http_listener_arn}" | jq -r '.Listeners[].DefaultActions[].TargetGroupArn' )
        echo ""
        echo "Live Target Group: ${live_target_group_arn}"
        echo "HTTP Target Group: ${http_target_group_arn}"
        echo ""
       
        echo ""
        echo "### REVIEWING LISTENERS to check if HTTP lister pointing to Live target group"
        echo ""
        if [[ ${live_target_group_arn} != ${http_target_group_arn} ]]; then
           
           echo "### Action: Change HTTP listener as live target group"
           aws --region ${awsRegion} elbv2 modify-listener --listener-arn ${http_listener_arn} --default-actions Type=forward,TargetGroupArn=${live_target_group_arn}
           if [[ $? -eq 0 ]]; then
               echo "### Live target group associated with HTTP listener"
           else
                echo "### ERROR: Failed to associate Live target group with HTTP listener"
                exit 1
           fi
           echo ""
           live_target_group_arn=$( aws --region ${awsRegion} elbv2 describe-listeners --listener-arns "${live_listener_arn}" | jq -r '.Listeners[].DefaultActions[].TargetGroupArn' )
           http_target_group_arn=$( aws --region ${awsRegion} elbv2 describe-listeners --listener-arns "${http_listener_arn}" | jq -r '.Listeners[].DefaultActions[].TargetGroupArn' )
           echo ""
           echo "Live Target Group: ${live_target_group_arn}"
           echo "HTTP Target Group: ${http_target_group_arn}"
           echo ""
        else
              echo "### Info: No Action Required. HTTP listener is having live target"
        fi
	else
		echo "ERROR: AssumeRole operation"
	fi
  
	rm -f awscre-${currentAWSAccount} 2>/dev/null
done
# end of loop for AWS Roles
done
# end of loop for AWS Regions
