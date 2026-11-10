#!/usr/bin/sh


# AWS_ROLE (currently configured to scan for below aws accounts)
#arn:aws:iam::665975628511:role/obi.dev.automation-jenkins
#arn:aws:iam::384335117118:role/obi.awsprod.automation-jenkins
#arn:aws:iam::580173953382:role/obi.prod.automation-jenkins
#arn:aws:iam::341006910668:role/subscriptions.devops.aws.dev.automation-jenkins
#arn:aws:iam::976186898275:role/subscriptions.devops.aws.prod.automation-jenkins
#arn:aws:iam::864643059465:role/subscriptions.dw.aws.dev.automation-jenkins
#arn:aws:iam::223159632293:role/subscriptions.dw.aws.prod.automation-jenkins
#arn:aws:iam::674961505149:role/subscriptions.frontends.aws.dev.automation-jenkins
#arn:aws:iam::559354210775:role/subscriptions.frontends.aws.prod.automation-jenkins
#arn:aws:iam::070623800947:role/subscriptions.obi-batch.aws.dev.automation-jenkins
#arn:aws:iam::754971227468:role/subscriptions.obi-batch.aws.prod.automation-jenkins
#arn:aws:iam::673664509050:role/subscriptions.obi-black.aws.prod.automation-jenkins
#arn:aws:iam::742442504506:role/subscriptions.obi-core.aws.dev.automation-jenkins
#arn:aws:iam::723694362115:role/subscriptions.obi-core.aws.prod.automation-jenkins
#arn:aws:iam::915970820886:role/subscriptions.obi-db.aws.dev.automation-jenkins
#arn:aws:iam::463676893277:role/subscriptions.obi-db.aws.prod.automation-jenkins
#arn:aws:iam::308363121193:role/subscriptions.obi-fe.aws.dev.automation-jenkins
#arn:aws:iam::625735167202:role/subscriptions.obi-fe.aws.prod.automation-jenkins
#arn:aws:iam::349874332661:role/subscriptions.scs.aws.dev.automation-jenkins
#arn:aws:iam::759254870277:role/subscriptions.scs.aws.prod.automation-jenkins
#arn:aws:iam::514990901328:role/subscriptions.services.aws.dev.automation-jenkins
#arn:aws:iam::594709372260:role/subscriptions.services.aws.prod.automation-jenkins
#arn:aws:iam::029944501988:role/customer-care.voc.aws.dev.automation-jenkins
#arn:aws:iam::920266445455:role/customer-care.voc.aws.prod.automation-jenkins

# AWS REGION (currently configured to scan for below aws regions)
#us-east-1
#us-east-2
#us-west-2
#ap-southeast-1
#eu-west-1

# ALLOWED_LIST_TO_EXCLUDE
# If a resource has a valid reason to be open, please add to the ALLOWED_LIST for not notifying. Like LB NAME, INSTANCE ID or CLOUDFRONT DISTRIBUTION ID.

#set -xue pipefail
#set +x

# update variable PRJ_HOME in new environment
#
prjHome=$(pwd); export prjHome
prjTmp=${prjHome}/tmp; export prjTmp
prjOut=${prjHome}/output; export prjOut
currentDt=$( date '+%Y-%m-%d' )
jenkinsIPaddress=$( hostname -I | awk '{print $1}' )


# remove the file if exists
#
mkdir -p ${prjTmp} ${prjOut}
rm -f ${prjTmp}/* 2>/dev/null
rm -f ${prjOut}/* 2>/dev/null


# read parameters from jenkins for allowed elbs (ALLOWED_ELBS) and ec2s (ALLOWED_EC2S)
#
ELB_EXCLUDE_LIST=""
EC2_EXCLUDE_LIST=""
CLOUDFRONT_EXCLUDE_LIST=""
#elbsAllowed=$( echo ${ALLOWED_ELBS} | sed "s/ [*]/ /g" | sed "s/ /','/g" | sed "s/^/['/g" | sed "s/$/']/g" ); export elbsAllowed
#ec2sAllowed=$( echo ${ALLOWED_EC2S} | sed "s/ [*]/ /g" | sed "s/ /','/g" | sed "s/^/['/g" | sed "s/$/']/g" ); export ec2sAllowed
#echo "elbsAllowed = ${elbsAllowed}"
#echo "ec2sAllowed = ${ec2sAllowed}"

cp ${prjHome}/automations/iam_roles.automations.txt ${prjOut}/iam_roles.txt



#
# Telnet
#
function getTelnetStatus() {
  hostNameOrIp=$1
  portNumber=$2
      
  telnetOut=$( echo quit | timeout --signal=9 2 telnet ${hostNameOrIp} ${portNumber} 2>/dev/null | egrep "Connected to" | wc -l )
  if [[ ${telnetOut} -eq 1 ]]; then
    telnetStatus="open"
  else
    telnetStatus="blocked"
  fi   
  echo ${telnetStatus}
}

#
# WAF
#
function getHttpStatus() {
  dnsName=$1
  portNumber=$2
  if [[ ${portNumber} -eq 443 ]]; then
    urlName="https://${dnsName}"
  elif [[ ${portNumber} -eq 80 ]]; then
    urlName="http://${dnsName}"
  else
    urlName="https://${dnsName}:${portNumber}"
  fi
         
  httpStatus403=$( curl -ILsk ${urlName} | egrep "HTTP" | egrep "403" | wc -l )
  if [[ ${httpStatus403} -eq 1 ]]; then
    httpStatus="blocked"
  else
    httpStatus="open"
  fi
  echo ${httpStatus}
}


#
# testOpenEndpoint
#
function checkOpenEndpoint() {
  fileName=$1
  cat ${fileName} | while read ep_line
  do
    epName=$( echo ${ep_line} | awk -F',' '{print $1}' )
    epDnsOrIp=$( echo ${ep_line} | awk -F',' '{print $2}' )
    epPort=$( echo ${ep_line} | awk -F',' '{print $3}' )
      
    if [[ ${epPort} == 'NA' ]] || [[ ${epPort} == 2222 ]]; then
      telnetStatus="skip"
    else
      telnetStatus=$( getTelnetStatus $epDnsOrIp $epPort )
    fi
    if [[ "${telnetStatus}" == "open" ]]; then
      #elb or elbv2 or cloudfront : check http status is 403
      if [[ $( echo ${fileName} | egrep "elb|elbv2|cloudfront" | wc -l ) -eq 1 ]]; then 
        httpStatus=$( getHttpStatus ${epDnsOrIp} ${epPort} )
        if [[ "${httpStatus}" == "open" ]]; then
          echo "OPEN --- telnet (${telnetStatus}) waf (open or not present) : [$ep_line]"                   
        else
          echo "     --- telnet (${telnetStatus}) waf (${httpStatus}) : [$ep_line]"
        fi
      #ec2 : we do not need any further check
      else
        echo "OPEN --- telnet (${telnetStatus}) : [$ep_line]"
      fi
    else
      echo "     --- telnet (${telnetStatus}) : [$ep_line]"
    fi
  done | tee -a ${prjOut}/open_endpoints_scan_result.all.txt
}
echo "# project-home      : ${prjHome}"
echo "# role-session-name : ${jenkinsIPaddress}"
echo "# current-timestamp : $( date '+%Y-%m-%d %H:%M')"
for currentAWSRole in ${AWS_ROLE}; do
for awsRegion in ${AWS_REGION}; do

  currentAWSAccount=$( echo ${currentAWSRole} | awk -F":" '{print $5}' )

  # skip to run non frontends-dev and frontends-prod account for us-west-2, ap-southeast-1, eu-west-1 
  if [[ $( echo ${currentAWSAccount} | egrep "674961505149|559354210775" | wc -l ) -eq 0 ]]; then
    if [[ $( echo ${awsRegion} | egrep "us-west-2|ap-southeast-1|eu-west-1" | wc -l ) -eq 1 ]] ; then
      break
    fi
  fi

  unset AWS_ACCESS_KEY_ID
  unset AWS_SECRET_ACCESS_KEY
  unset AWS_SECURITY_TOKEN

  aws sts assume-role --region ${awsRegion} --role-arn ${currentAWSRole} --role-session-name ${jenkinsIPaddress} 2>awscre-${currentAWSAccount}.err | \
  grep -w 'AccessKeyId\|SecretAccessKey\|SessionToken' | \
  sed 's/\"//g;s/\,//;s/ //g' > awscre-${currentAWSAccount} ;\

  if [[ -s awscre-${currentAWSAccount}.err ]]; then
    if [[ $( cat awscre-${currentAWSAccount}.err | egrep "RegionDisabledException" | wc -l ) -eq 1 ]]; then
      echo "## --------------------------------------------------------------------"
      echo "## awsAccount        : ${currentAWSAccount}"
      echo "## awsRegion         : ${awsRegion}"
      echo "##"
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

    echo "## --------------------------------------------------------------------"
    echo "## awsAccount        : ${currentAWSAccount} - ${currentAWSAccountAlias}"
    echo "## awsRegion         : ${awsRegion}"
    echo "##"
    
    #
    # elb
    #
    elbNames=$( aws --region ${awsRegion} elb describe-load-balancers | jq -r '.LoadBalancerDescriptions[].LoadBalancerName' )
    #elbNames=''
    elbNames_array=(${elbNames})
    echo "Reading ${#elbNames_array[@]} load balancers (classic)"

    if [[ ${#elbNames_array[@]} -ne 0 ]]; then
      for elbName in ${elbNames_array[@]}; do
        
        aws --region ${awsRegion} elb describe-load-balancers --load-balancer-name ${elbName} >${prjTmp}/elb.json
        
        lbName=$( cat ${prjTmp}/elb.json | jq -r '.LoadBalancerDescriptions[].LoadBalancerName' )
        lbType=$( cat ${prjTmp}/elb.json | jq -r '.LoadBalancerDescriptions[].Type' | tr 'A-Z' 'a-z')
        lbDnsName=$( cat ${prjTmp}/elb.json | jq -r '.LoadBalancerDescriptions[].DNSName' )
        lbArn=$( cat ${prjTmp}/elb.json | jq -r '.LoadBalancerDescriptions[].LoadBalancerArn' )
        lbScheme=$( cat ${prjTmp}/elb.json | jq -r '.LoadBalancerDescriptions[].Scheme' )
        #INFO:echo "lbScheme:${lbScheme}"
        if [[ "${lbScheme}" == "internet-facing" ]]; then
          lbPorts=$( cat ${prjTmp}/elb.json | jq -r '.LoadBalancerDescriptions[].ListenerDescriptions[].Listener.LoadBalancerPort' )
          lbPorts_array=(${lbPorts})
          for lbPort in ${lbPorts_array[@]}; do
            echo "${lbName},${lbDnsName},${lbPort}"
          done
        fi
      done >${prjTmp}/elb.csv

      if [[ -s ${prjTmp}/elb.csv ]]; then
        echo "Reading $( cat ${prjTmp}/elb.csv 2>/dev/null | awk -F',' '{print $1}' | sort -u | wc -l ) load balancers (classic) that are internet-facing"
        # call checkOpenEndpoint
        checkOpenEndpoint ${prjTmp}/elb.csv
      else
        echo "Reading 0 load balancers (classic) that are internet-facing"
      fi
    fi

    #
    # elbv2
    #
    elbv2Arns=$( aws --region ${awsRegion} elbv2 describe-load-balancers | jq -r '.LoadBalancers[].LoadBalancerArn' )
    #elbv2Arns=''
    elbv2Arns_array=(${elbv2Arns})
    echo "Reading ${#elbv2Arns_array[@]} load balancers (alb,nlb)"

    if [[ ${#elbv2Arns_array[@]} -ne 0 ]]; then
      for elbv2Arn in ${elbv2Arns_array[@]}; do
        
        aws --region ${awsRegion} elbv2 describe-load-balancers --load-balancer-arns ${elbv2Arn} >${prjTmp}/elbv2.json
        
        lbName=$( cat ${prjTmp}/elbv2.json | jq -r '.LoadBalancers[].LoadBalancerName' )
        lbType=$( cat ${prjTmp}/elbv2.json | jq -r '.LoadBalancers[].Type' )
        lbDnsName=$( cat ${prjTmp}/elbv2.json | jq -r '.LoadBalancers[].DNSName' )
        lbArn=$( cat ${prjTmp}/elbv2.json | jq -r '.LoadBalancers[].LoadBalancerArn' )
        lbScheme=$( cat ${prjTmp}/elbv2.json | jq -r '.LoadBalancers[].Scheme' )
        #INFO:echo "lbScheme:${lbScheme}"
        if [[ "${lbScheme}" == "internet-facing" ]]; then
          lbPorts=$( aws --region ${awsRegion} elbv2 describe-listeners --load-balancer-arn ${elbv2Arn} | jq -r '.Listeners[] | select(.DefaultActions[].Type == "forward") | .Port' )
          lbPorts_array=(${lbPorts})
          for lbPort in ${lbPorts_array[@]}; do
            echo "${lbName},${lbDnsName},${lbPort}"
          done
        fi
      done >${prjTmp}/elbv2.csv

      if [[ -s ${prjTmp}/elbv2.csv ]]; then
        echo "Reading $( cat ${prjTmp}/elbv2.csv 2>/dev/null | awk -F',' '{print $1}' | sort -u | wc -l ) load balancers (alb,nlb) that are internet-facing"
        # call checkOpenEndpoint
        checkOpenEndpoint ${prjTmp}/elbv2.csv
      else
        echo "Reading 0 load balancers (alb,nlb) that are internet-facing"
      fi
    fi

    #
    # ec2
    #
    ec2InstanceIds=$( aws --region ${awsRegion} ec2 describe-instances | jq -r '.Reservations[].Instances[].InstanceId' )
    #ec2InstanceIds=''
    ec2InstanceIds_array=(${ec2InstanceIds})
    echo "Reading ${#ec2InstanceIds_array[@]} ec2 instances"
    
    if [[ ${#ec2InstanceIds_array[@]} -ne 0 ]]; then
      for ec2InstanceId in ${ec2InstanceIds_array[@]}; do
        
        aws --region ${awsRegion} ec2 describe-instances --instance-ids ${ec2InstanceId} >${prjTmp}/ec2.json 
        
        instanceState=$( cat ${prjTmp}/ec2.json | jq -r '.Reservations[].Instances[].State.Name' )
        instancePublicIp=$( cat ${prjTmp}/ec2.json | jq -r '.Reservations[].Instances[] | select((.PublicIpAddress|length)>=1) | .PublicIpAddress' )
        #echo "INFO:instancePublicIp:${instancePublicIp}"
        if [[ ! -z "${instancePublicIp}" ]]; then
          #echo "INFO:instanceState:${instanceState}"
          if [[ "${instanceState}" != "stopped" ]]; then
            instanceSecurityGroupIds=$( cat ${prjTmp}/ec2.json | jq -r '.Reservations[].Instances[].SecurityGroups[].GroupId' )
            instanceSecurityGroupIds_array=(${instanceSecurityGroupIds})
            for instanceSecurityGroupId in ${instanceSecurityGroupIds_array[@]}; do
              instancePorts=$( aws --region ${awsRegion} ec2  describe-security-groups --group-ids ${instanceSecurityGroupId} | jq -r '.SecurityGroups[].IpPermissions[].ToPort' )
              instancePorts_array=(${instancePorts})
              if [[ ${#instancePorts_array[@]} -ne 0 ]]; then
                for instancePort in ${instancePorts_array[@]}; do
                  echo "${ec2InstanceId},${instancePublicIp},${instancePort}"
                done
              else
                echo "${ec2InstanceId},${instancePublicIp},NA"
              fi
            done
          fi
        fi
      done >${prjTmp}/ec2.csv

      if [[ -s ${prjTmp}/ec2.csv ]]; then
        echo "Reading $( cat ${prjTmp}/ec2.csv 2>/dev/null | awk -F',' '{print $1}' | sort -u | wc -l ) ec2 instances that have publicIP and not stopped"
        # call checkOpenEndpoint
        checkOpenEndpoint ${prjTmp}/ec2.csv
      else
        echo "Reading 0 ec2 instances that have publicIP and not stopped"
      fi
    fi

    #
    # cloudfront
    #
    
    #cloudfront is a global resource so running only for us-east-1
    if [[ ${awsRegion} == "us-east-1" ]]; then
      cfDistributionIds=$( aws --region ${awsRegion} cloudfront list-distributions | jq -r '.DistributionList.Items[].Id' )
      #cfDistributionIds=''
      cfDistributionIds_array=(${cfDistributionIds})
      echo "Reading ${#cfDistributionIds_array[@]} cloudfront distributions"
    
      if [[ ${#cfDistributionIds_array[@]} -ne 0 ]]; then
        for cfDistributionId in ${cfDistributionIds_array[@]}; do
        
          cfDistributionDomainName=$( aws --region ${awsRegion} cloudfront list-distributions | jq -r --arg cfDistributionId "${cfDistributionId}" '.DistributionList.Items[] | select(.Id == $cfDistributionId) | .DomainName' )
          cfDistributionEnabledStatus=$( aws --region ${awsRegion} cloudfront list-distributions | jq -r --arg cfDistributionId "${cfDistributionId}" '.DistributionList.Items[] | select(.Id == $cfDistributionId) | .Enabled' )
          #echo "INFO:cfDistributionId:${cfDistributionId}"
          if [[ ! -z "${cfDistributionEnabledStatus}" ]]; then
            #echo "INFO:cfDistributionEnabledStatus:${cfDistributionEnabledStatus}"
            if [[ "${cfDistributionEnabledStatus}" != "false" ]]; then
              cfDistributionPorts_array=(80 443)
              if [[ ${#cfDistributionPorts_array[@]} -ne 0 ]]; then
                for cfDistributionPort in ${cfDistributionPorts_array[@]}; do
                  echo "${cfDistributionId},${cfDistributionDomainName},${cfDistributionPort}"
                done
              else
                echo "${cfDistributionId},${cfDistributionDomainName},NA"
              fi
            fi
          fi
        done >${prjTmp}/cloudfront.csv

        if [[ -s ${prjTmp}/cloudfront.csv ]]; then
          echo "Reading $( cat ${prjTmp}/cloudfront.csv 2>/dev/null | awk -F',' '{print $1}' | sort -u | wc -l ) cloudfront distributions that are enabled"
          # call checkOpenEndpoint
          checkOpenEndpoint ${prjTmp}/cloudfront.csv
        else
          echo "Reading 0 cloudfront distributions that are enabled"
        fi
      fi
    fi
    
  else
    echo "ERROR: AssumeRole operation"
  fi

  rm -f awscre-${currentAWSAccount} 2>/dev/null
done
# end of loop for AWS Regions
done
# end of loop for AWS Roles


# create list of all open endpoints
cat ${prjOut}/open_endpoints_scan_result.all.txt | egrep OPEN >${prjOut}/open_endpoints_scan_result.open.txt

# create list of open endpoints exclusing the allowed list
echo "INFO: Excluding below resources from open endpoints scan"
echo "------------------------------"
echo ${ALLOWED_LIST_TO_EXCLUDE} | tr ' ' '\n'
echo "------------------------------"
echo ${ALLOWED_LIST_TO_EXCLUDE} | tr ' ' '\n' | sed "s/^/\\\\[/g" | sed "s/$/,/g" >${prjTmp}/allow_list.txt
cat ${prjOut}/open_endpoints_scan_result.open.txt | egrep -v -f ${prjTmp}/allow_list.txt >${prjOut}/open_endpoints_scan_result.open.final.txt

echo "*******************************"
echo "INFO: No Open Public End points"
# if the list has open public end points then the job fails to trigger OpsGenie alert via post build actions
if [[ -s ${prjOut}/open_endpoints_scan_result.open.final.txt ]]; then
  num_open_endpoints=$( cat ${prjOut}/open_endpoints_scan_result.open.final.txt | egrep OPEN | awk -F'[' '{print $2}' | awk -F',' '{print $1}' | sort -u | wc -l )
  if [[ ${num_open_endpoints} -ge 1 ]]; then
    echo "***************************************************************"
    echo "ERROR: We have ${num_open_endpoints} Open Public End points. Sending notification."
    echo "***************************************************************"
    cat ${prjOut}/open_endpoints_scan_result.open.final.txt
    exit 1
  else
    echo "*******************************"
    echo "INFO: No Open Public End points"
    echo "*******************************"
  fi
fi 
    
set -x
