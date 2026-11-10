#!/bin/sh

if [ $# -eq 2 ]; then

scriptName=$0
dbUser=$1
dbPass=$2
jenkinsIPaddress=$( hostname -I | awk '{print $1}' )
runDt=$( date '+%Y-%m-%d' )
cts=$( date '+%Y%m%d-%H%M' )
RPT_FILE="/tmp/license_server_report.rpt.${cts}.html"
fromEmail="do-not-reply@yahoo.net"
alarm_flag=0
hostName=$( hostname )
toEmail="anil.dalli@yahooinc.com,gandhi.srinivasan@yahooinc.com,shilpa.vontikommu@yahooinc.com,jagadeesh.aluri@yahooinc.com,scott.dorfman@yahooinc.com"
toEmailDev="anil.dalli@yahooinc.com,gandhi.srinivasan@yahooinc.com,karthik.bheemanadula@yahooinc.com,pratik.mohanty@yahooinc.com"
#toEmail="anil.dalli@yahooinc.com,gandhi.srinivasan@yahooinc.com"
#toEmailDev="anil.dalli@yahooinc.com,gandhi.srinivasan@yahooinc.com"

echo "###########: Start script ${scriptName} is running on host ${hostName}"

. /home/ec2-user/.profile

function email_report_func(){

echo "###########: Sending email..."
echo "Email From : ${FROM_EMAIL}"
echo "Email To   : ${TO_EMAIL}"
echo "Subject    : ${RPT_SUBJ}"
echo "Body       : ${RPT_BODY}"
echo "###########"

(
cat << --OEF--
From: ${FROM_EMAIL}
To: ${TO_EMAIL}
Subject: ${RPT_SUBJ}
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="MAIL_BOUNDARY"
--MAIL_BOUNDARY
Content-Type: text/html; charset=utf-8
Content-Disposition: inline
--OEF--
cat ${RPT_BODY}
echo "--MAIL_BOUNDARY--"
) |  /usr/sbin/sendmail -f "${FROM_EMAIL}" "${TO_EMAIL}"
}

# 
# the SQLs to get License Server Report
dbHost="rds-license-server.subscriptions-obi-fe-aws-prod.aws.oath.cloud"
dbPort="3306"
dbName="obi_licensing_service"

mysql --silent --skip-column-names -u "${dbUser}" -p"${dbPass}" -h "${dbHost}" -P "${dbPort}" -D "${dbName}"  >/tmp/license_server_report.out 2>&1 <<YYY

SELECT CONCAT(api_name, ',', status_code, ',', COUNT(*))
    FROM obi_licensing_service.TRANSACTIONS 
    WHERE created_dt >= NOW() - INTERVAL 1 DAY 
    GROUP BY api_name, status_code;
YYY

cat /tmp/license_server_report.out| egrep -v "Warning|^$" | sed "s/	//g" >/tmp/license_server_report.fmt.out

echo ""
echo "### INFO: Get Downloads count from Cloudwatch"
echo ""

yest_dt=$(date -d "yesterday" +%Y-%m-%d)
todays_dt=$(date +%Y-%m-%d)
start_dt_epc=$(date -d "${yest_dt} 00:00:00" +%s)
end_dt_epc=$(date -d "${todays_dt} 00:00:00" +%s)

echo "### INFO: Role"
aws sts get-caller-identity
currentAWSRole="arn:aws:iam::625735167202:role/subscriptions.obi-fe.aws.prod.automation-jenkins"
currentAWSAccount=$( echo ${currentAWSRole} | awk -F":" '{print $5}' )

unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SECURITY_TOKEN

echo "### INFO: Assuming Role ${currentAWSRole}"
aws sts assume-role --region "us-east-1" --role-arn ${currentAWSRole} --role-session-name ${jenkinsIPaddress} 2>awscre-${currentAWSAccount}.err | \
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

echo "### INFO: Role"
aws sts get-caller-identity

cw_log_group_name="aws-waf-logs-license-service-fe"

query_id=$( aws logs start-query --log-group-name "${cw_log_group_name}" --start-time ${start_dt_epc} --end-time ${end_dt_epc} --query-string "fields httpRequest.uri, httpRequest.httpMethod, action | filter httpRequest.httpMethod = \"GET\" and httpRequest.uri like /\/download\/SearchandRecoverSetup\.exe/ and action = \"ALLOW\" | stats count(*) as DAILY_COUNT by bin(1d) as DOWNLOAD_DATE | sort DOWNLOAD_DATE desc | display DOWNLOAD_DATE, DAILY_COUNT" --region us-east-1 | jq -r '.queryId' )
echo "### INFO: Query ID - ${query_id}"
yest_dt_cw="${yest_dt} 00:00:00.000"
aws --region us-east-1 logs get-query-results --query-id ${query_id} | jq --arg mydt "$yest_dt_cw" -r '.results[] | select(.[].value == $mydt) | .[] | select(.field == "DAILY_COUNT") | .value'
download_cnt=$( aws --region us-east-1 logs get-query-results --query-id ${query_id} | jq --arg mydt "$yest_dt_cw" -r '.results[] | select(.[].value == $mydt) | .[] | select(.field == "DAILY_COUNT") | .value' )
if [[ -z ${download_cnt} ]]; then
	download_cnt=0
fi
echo ""
echo "Downloads,,${download_cnt}" >>/tmp/license_server_report.fmt.out
echo ""

if [[ $( cat /tmp/license_server_report.fmt.out | egrep "ERROR" | wc -l ) -ge 1 ]]; then
	echo "Error: MYSQL errors found..."
	echo "<html><body><h3><br><br>Pls check MYSQL errors found...<br></h3>" 				>${RPT_FILE}
	echo "<font color="red">$( cat /tmp/license_server_report.fmt.out )</font><br><br></body></html>" 	>>${RPT_FILE}
	alarm_flag=2
else

	echo "<table style=\"width:60%\">"  																	>${RPT_FILE}
	echo "<h3><br><br>License Server Report<br></h3>"         				>>${RPT_FILE}
	echo "<tr bgcolor="lightgrey"><th>NAME</th><th>STATUS_CODE</th><th>COUNT</th></tr>"	>>${RPT_FILE}

	cat /tmp/license_server_report.fmt.out | while read line
	do
		col1=$( echo "${line}" | awk -F',' '{print $1}' )
		col2=$( echo "${line}" | awk -F',' '{print $2}' )
		col3=$( echo "${line}" | awk -F',' '{print $3}' )
		echo "<tr><td>${col1}</td><td>${col2}</td><td>${col3}</td></tr>"										>>${RPT_FILE}
	done		
	echo "</table>"																											>>${RPT_FILE}
fi

FROM_EMAIL=${fromEmail}
RPT_BODY=${RPT_FILE}

if [[ ${alarm_flag} -eq 2 ]]; then
	RPT_SUBJ="Error : License Server Report for ${yest_dt}"
	TO_EMAIL=${toEmailDev}
	# send email notification
	email_report_func
	exit 1
else
	RPT_SUBJ="License Server Report : ${runDt}"
	TO_EMAIL=${toEmail}
	# send email notification
	email_report_func
fi

	rm -f ${RPT_FILE}		2>/dev/null

else
	echo "Usage: <script_name> <dbuser> <dbpassword>"
fi
