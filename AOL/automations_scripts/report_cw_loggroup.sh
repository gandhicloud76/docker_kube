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

for currentAWSRole in ${AWS_ROLE}; do

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

		aws --region us-east-1 logs describe-log-groups | jq --arg RETENTION_DAYS_GREATER_THAN_FILTER "${RETENTION_DAYS_GREATER_THAN_FILTER}" --arg SIZE_GB_LESS_THAN_FILTER "${SIZE_GB_LESS_THAN_FILTER}" -r '.logGroups[] | select(.retentionInDays > '$RETENTION_DAYS_GREATER_THAN_FILTER') | select(.storedBytes/1024/1024/1024 > '$SIZE_GB_LESS_THAN_FILTER') | {logGroupName,retentionInDays,storedBytes}' >${prjOut}/cw_lg.raw
		
        if [[ -s ${prjOut}/cw_lg.raw ]]; then
        	  cat ${prjOut}/cw_lg.raw | jq -r '.logGroupName' 	>${prjOut}/cw_lg.col1
            cat ${prjOut}/cw_lg.raw | jq -r '.retentionInDays' 	>${prjOut}/cw_lg.col2
            cat ${prjOut}/cw_lg.raw | jq -r '.storedBytes' 		>${prjOut}/cw_lg.col3
            
            paste -d"," ${prjOut}/cw_lg.col1 ${prjOut}/cw_lg.col2 ${prjOut}/cw_lg.col3 | sed "s/^/${currentAWSAccount},${currentAWSAccountAlias},/g" >>${prjOut}/report.csv
        else
            echo "SKIP: No CW log group matching our filter criteria i.e. Retention > $RETENTION_DAYS_GREATER_THAN_FILTER days and Size > $SIZE_GB_LESS_THAN_FILTER GB"
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
<h3>Cloudwatch log Group (Retention > $RETENTION_DAYS_GREATER_THAN_FILTER days and Size > $SIZE_GB_LESS_THAN_FILTER) GB - ${currentDt}</h3>
<body>
<table border="1">
<tr>
<th bgcolor="lightblue">AWS Account</th>
<th bgcolor="lightblue">AWS Account Name</th>
<th bgcolor="lightblue">CW log group name</th>
<th bgcolor="lightblue">Retention In Days</th>
<th bgcolor="lightblue">Storage Bytes (GB)</th>
</tr>"	>${prjOut}/report.html

cat ${prjOut}/report.csv | sort -u | sort -t',' -k1,1 -k2,2 -k3,3 -k4,4	>${prjOut}/report.fmt.csv

if [ -s ${prjOut}/report.fmt.csv ]; then
	cat ${prjOut}/report.fmt.csv | while read x
	do
		col1=$( echo $x | awk -F"," '{print $1}' )
		col2=$( echo $x | awk -F"," '{print $2}' )
		col3=$( echo $x | awk -F"," '{print $3}' )
		col4=$( echo $x | awk -F"," '{print $4}' )
		col5=$( echo $x | awk -F"," '{print $5}' )
        col5_fmt=$( echo "$col5 / 1024 / 1024 / 1024" | bc )

		fg_color="black"
        if [ ${col5_fmt} -gt 50 ] || [ ${col4} -gt 91 ]; then
        	fg_color="red"
        fi

		echo "<tr>
		<td><font color=${fg_color}>${col1}</font></td>
		<td><font color=${fg_color}>${col2}</font></td>
		<td><font color=${fg_color}>${col3}</font></td>
		<td><font color=${fg_color}>${col4}</font></td>
		<td><font color=${fg_color}>${col5_fmt}</font></td>
		</tr>"	>>${prjOut}/report.html
	done
else
	echo "<tr>Report NA</tr>"
fi
echo "</table><br><h4>Note:In red, if retention is more than 91 days or size is more than 50 gb</h4></body></html>"	>>${prjOut}/report.html

set -x
