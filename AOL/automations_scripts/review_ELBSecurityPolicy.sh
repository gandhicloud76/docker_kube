#!/usr/bin/sh


# AWS_ROLE
# AWS REGION

#set -xue pipefail
#set +x

# update variable PRJ_HOME in new environment
#
prjHome=$(pwd); export prjHome
prjTmp=${prjHome}/tmp; export prjTmp
prjOut=${prjHome}/output; export prjOut
currentDt=$( date '+%Y-%m-%d' )
jenkinsIPaddress=$( hostname -I | awk '{print $1}' )

# called while building HTML page
header() {
cat<<-EOF
<head>
<script src="https://ajax.googleapis.com/ajax/libs/jquery/1.11.2/jquery.min.js" type="text/javascript"></script>
<link rel="stylesheet" type="text/css" href="https://cdn.datatables.net/1.11.2/css/jquery.dataTables.css">
<script type="text/javascript" charset="utf8" src="https://cdn.datatables.net/1.11.2/js/jquery.dataTables.js"></script>

<script>
\$(document).ready( function () {
    var indexLastColumn = \$("#myTable").find('tr')[0].cells.length-1;
    \$('#myTable').DataTable({
    "pageLength": 100,
    "order":[[indexLastColumn,'desc']]
    });
} );
</script>
</head>
EOF
}

# remove the file if exists
#
mkdir -p ${prjOut}
rm -f ${prjOut}/* 2>/dev/null

cp ${prjHome}/automations/iam_roles.automations.txt ${prjOut}/iam_roles.txt

echo "# project-home      : ${prjHome}"
echo "# role-session-name : ${jenkinsIPaddress}"
echo "# current-timestamp : $( date '+%Y-%m-%d %H:%M')"
AWS_REGION="us-east-1 us-east-2 us-west-2 eu-west-1 ap-southeast-1"
for currentAWSRole in ${AWS_ROLE}; do
for awsRegion in ${AWS_REGION}; do

  currentAWSAccount=$( echo ${currentAWSRole} | awk -F":" '{print $5}' )
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

    echo "## --------------------------------------------------------------------"
    echo "## awsAccount        : ${currentAWSAccount} - ${currentAWSAccountAlias}"
    echo "## awsRegion         : ${awsRegion}"
    echo "##"

    #
    # elbv2
    #
    elbv2Arns=$( aws --region ${awsRegion} elbv2 describe-load-balancers | jq -r '.LoadBalancers[].LoadBalancerArn' )
    #elbv2Arns=''
    elbv2Arns_array=(${elbv2Arns})
    echo "Reading ${#elbv2Arns_array[@]} load balancers (elbv2)"

    if [[ ${#elbv2Arns_array[@]} -ne 0 ]]; then
      for elbv2Arn in ${elbv2Arns_array[@]}; do
        
        aws --region ${awsRegion} elbv2 describe-load-balancers --load-balancer-arns ${elbv2Arn} >${prjOut}/elbv2.json
        
        lbName=$( cat ${prjOut}/elbv2.json | jq -r '.LoadBalancers[].LoadBalancerName' )
        lbType=$( cat ${prjOut}/elbv2.json | jq -r '.LoadBalancers[].Type' )
        lbScheme=$( cat ${prjOut}/elbv2.json | jq -r '.LoadBalancers[].Scheme' )
        lbPort_sslPolicy_all=$( aws --region ${awsRegion} elbv2 describe-listeners --load-balancer-arn ${elbv2Arn} --query 'Listeners[].[Port,SslPolicy]' --output text | awk '{print $1":"$2}' )
        lbPort_sslPolicy_all_array=(${lbPort_sslPolicy_all})
        for lbPort_sslPolicy in ${lbPort_sslPolicy_all_array[@]}; do
          lbPort=$( echo ${lbPort_sslPolicy} | awk -F':' '{print $1}' )
          sslPolicy=$( echo ${lbPort_sslPolicy} | awk -F':' '{print $2}' )
          if [[ ${sslPolicy} == "ELBSecurityPolicy-TLS13-1-2-2021-06" ]]  || [[ ${sslPolicy} == "None" ]]; then
            sslPolicy_flag=0
          else
            sslPolicy_flag=1
          fi
          echo "${currentAWSAccount},${currentAWSAccountAlias},${lbName},${lbType},${lbScheme},${lbPort},${sslPolicy},${sslPolicy_flag}"
        done
      done >>${prjOut}/report.elb_security_policy.csv
    fi   
  else
    echo "ERROR: AssumeRole operation"
  fi

  rm -f ${prjOut}/awscre-${currentAWSAccount} 2>/dev/null
done
# end of loop for AWS Regions
done
# end of loop for AWS Roles

# Create HTML report
echo "<html>
`header`
<h3>ELB Security Policy - ${currentDt}</h3>
<h4>Note: Enable ELBs to support TLSv1.2 and above security policy. Ex: ELBSecurityPolicy-TLS13-1-2-2021-06</h4>
<body>
<table border="1">
<tr>
<th bgcolor="lightblue">AWS Account Number</th>
<th bgcolor="lightblue">AWS Account Name</th>
<th bgcolor="lightblue">ELB Namet</th>
<th bgcolor="lightblue">ELB Type</th>
<th bgcolor="lightblue">Scheme</th>
<th bgcolor="lightblue">Port</th>
<th bgcolor="lightblue">Security Policy Name</th>
</tr>"  >${prjOut}/report.elb_security_policy.html

if [ -s ${prjOut}/report.elb_security_policy.csv ]; then
  cat ${prjOut}/report.elb_security_policy.csv | while read x
  do
    row_col=""
    col1=$( echo $x | awk -F"," '{print $1}' )
    col2=$( echo $x | awk -F"," '{print $2}' )
    col3=$( echo $x | awk -F"," '{print $3}' )
    col4=$( echo $x | awk -F"," '{print $4}' )
    col5=$( echo $x | awk -F"," '{print $5}' )
    col6=$( echo $x | awk -F"," '{print $6}' )
    col7=$( echo $x | awk -F"," '{print $7}' )
    col8=$( echo $x | awk -F"," '{print $8}' )
    if [[ ${col8} -eq 1 ]]; then row_col="red"; fi
    echo "<tr>
    <td><font color=${row_col}>${col1}</font></td>
    <td><font color=${row_col}>${col2}</font></td>
    <td><font color=${row_col}>${col3}</font></td>
    <td><font color=${row_col}>${col4}</font></td>
    <td><font color=${row_col}>${col5}</font></td>
    <td><font color=${row_col}>${col6}</font></td>
    <td><font color=${row_col}>${col7}</font></td>
    </tr>"  >>${prjOut}/report.elb_security_policy.html
  done
else
  echo "<tr>Report NA</tr>"
fi
echo "</table></body></html>" >>${prjOut}/report.elb_security_policy.html
set -x

