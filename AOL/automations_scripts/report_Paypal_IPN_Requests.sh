#!/bin/sh

if [ $# -eq 4 ]; then

scriptName=$0
dbPrdUser=$1
dbPrdPass=$2
dbArUser=$3
dbArPass=$4
jenkinsIPaddress=$( hostname -I | awk '{print $1}' )
runDt=$( date '+%Y-%m-%d' )
cts=$( date '+%Y%m%d-%H%M' )
RPT_FILE="/tmp/paypal_requests.rpt.${cts}.html"
fromEmail="do-not-reply@yahoo.net"
alarm_flag=0
hostName=$( hostname )
toEmail="anil.dalli@yahooinc.com,shilpa.vontikommu@yahooinc.com,sangeeta.bhatia@yahooinc.com,gandhi.srinivasan@yahooinc.com,pratik.mohanty@yahooinc.com,karthik.bheemanadula@yahooinc.com"
#toEmail="gandhi.srinivasan@yahooinc.com,anil.dalli@yahooinc.com"
toEmailDev="anil.dalli@yahooinc.com,gandhi.srinivasan@yahooinc.com,pratik.mohanty@yahooinc.com,karthik.bheemanadula@yahooinc.com"

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
# the SQLs to get Paypal IPN Requests Report

sqlplus -S ${dbPrdUser}/"${dbPrdPass}"@'(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-bpsprd1-new.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021))(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-bpsprd1.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021)))(CONNECT_DATA=(SERVICE_NAME=BPS_PRD)))' >/tmp/paypal_requests.out 2>&1 <<XXX
SET head off
SET feedback off
SET linesize 2000
SET COLSEP '|'
-- Total Number of Paypal Requests
select '001,Paypal Requests,' || count(*) 
    from obi_transaction_log 
    where created_dt > (sysdate - 1) and api_name='processPaypalIPN'
union
-- Total Number of Billing Agreement Cancels
select '002,Billing Agreement Cancels,' || count(*) 
    from obi_transaction_log 
    where created_dt > (sysdate - 1) and api_name='processPaypalIPN' and request like '%mp_cancel%'
union
--Total Number of Billing Agreement Signup
select '003,Billing Agreement Signup,' || count(*)
	from obi_transaction_log 
	where created_dt > (sysdate - 1) and api_name='processPaypalIPN' and request like '%mp_signup%'
union
--Total Number of Payments 
select '004,Payments,' || count(*) 
	from obi_transaction_log 
	where created_dt > (sysdate - 1) and api_name='processPaypalIPN' and request like '%merch_pmt%'
union
--Total Number of Billing Agreement Notifications 
select '005,Billing Agreement Notifications,' || count(*) 
	from obi_transaction_log 
	where created_dt > (sysdate - 1) and api_name='processPaypalIPN' and request like '%mp_notification%'
union
-- Total Number of Billing Agreement Cancels for Yahoo Reseller
select '006,Billing Agreement Cancels for Yahoo Reseller,' || count(*) 
    from obi_transaction_log 
    where created_dt > (sysdate - 1) and api_name='processPaypalIPN' and request like '%Yahoo+to+bill%' and request like '%mp_cancel%'
union
-- Total Number of Billing Agreement Cancels for EMEA
select '007,Billing Agreement Cancels for EMEA,' || count(*) 
    from obi_transaction_log 
    where created_dt > (sysdate - 1) and api_name='processPaypalIPN' and request like '%Verizon+Media+EMEA%' and request like '%mp_cancel%'
union
-- Total Number of Billing Agreement Cancels for AOL
select '008,Billing Agreement Cancels for AOL,' || count(*) 
    from obi_transaction_log 
    where created_dt > (sysdate - 1) and api_name='processPaypalIPN' and request like '%AOL+to+bill%' and request like '%mp_cancel%'
union
-- Total Number of Billing Agreement Cancels for Rivals
select '009,Billing Agreement Cancels for Rivals,' || count(*) 
    from obi_transaction_log 
    where created_dt > (sysdate - 1) and api_name='processPaypalIPN' and request like '%Yahoo+(Rivals)%' and request like '%mp_cancel%';
exit;
XXX

sqlplus -S ${dbArUser}/"${dbArPass}"@'(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-obiardb2.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021))(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-obiardb1.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021)))(CONNECT_DATA=(SERVICE_NAME=OBIAR)))' >/tmp/action_id_2242.out 2>&1 <<YYY
SET head off
SET feedback off
SET linesize 2000
SET COLSEP '|'
--SVU actions for paypal billing agreement cancel
select '2242,' || count(*) 
    from obi_svu_transaction_log 
    where created_dt > (sysdate-1) and action_id=2242;
exit;
YYY


echo ""
echo "### INFO: SQL output of paypal_requests"
cat /tmp/paypal_requests.out
TOTAL_PAYPAL_REQUESTS=$( cat /tmp/paypal_requests.out | egrep "^001,Paypal Requests," | awk -F',' '{print $NF}' )
TOTAL_BILLING_AGREEMENT_CANCELS=$( cat /tmp/paypal_requests.out | egrep "^002,Billing Agreement Cancels," | awk -F',' '{print $NF}' )
echo ""
echo "### INFO: SQL output of action_id_2242"
cat /tmp/action_id_2242.out
TOTAL_SVU_ACTIONS=$( cat /tmp/action_id_2242.out | egrep "^2242," | awk -F',' '{print $NF}' )
echo ""

echo ""
echo "### INFO: Running reports on SNS topics and S3 logs"
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

echo ""
echo "###"
echo "### Get SNS topic status for ${yest_dt}"
echo "###"

sns_cw_log_group_name="sns/us-east-1/625735167202/obi_paypal_ipn_sns_verified"

query_id=$( aws logs start-query --log-group-name "${sns_cw_log_group_name}" --start-time ${start_dt_epc} --end-time ${end_dt_epc} --query-string "fields @message | parse @message '\"status\":\"*\"' as status | stats count() as StatusCount by status" --region us-east-1 | jq -r '.queryId' )
echo "### INFO: Query ID - ${query_id}"
aws --region us-east-1 logs get-query-results --query-id ${query_id} | jq -r '.results[0] | map({(.field): .value}) | add' | jq -r '.status + "," + .StatusCount' >/tmp/paypal_ipn_sns_requests.out
echo ""
echo "### INFO: AWSCLI output of paypal_ipn_sns_requests"
cat /tmp/paypal_ipn_sns_requests.out
TOTAL_SNS_REQUESTS=$( cat /tmp/paypal_ipn_sns_requests.out | awk -F',' '{sum += $2} END {print sum}' )
echo ""

echo "###"
echo "### Get Success/Error count from S3 bucket for ${yest_dt}"
echo "###"
bucket_name="s3://obi-paypal-ipn-prod/logs/"
aws s3 ls ${bucket_name} --query "Contents[].[Key, LastModified]" --output text | egrep "^${yest_dt}" | awk -F'.' '{print $1}' | sed "s/-log//g" | awk '{print $NF}' | sort | uniq -c | awk '{print $2","$1}' >/tmp/paypal_ipn_s3_logs.out
echo ""
echo "### INFO: AWSCLI output of paypal_ipn_s3_logs"
cat /tmp/paypal_ipn_s3_logs.out
echo ""

echo ""
echo "### INFO: TOTAL_SNS_REQUESTS              : ${TOTAL_SNS_REQUESTS}"
echo "### INFO: TOTAL_PAYPAL_REQUESTS           : ${TOTAL_PAYPAL_REQUESTS}"
echo ""
echo "### INFO: TOTAL_BILLING_AGREEMENT_CANCELS : ${TOTAL_BILLING_AGREEMENT_CANCELS}"
echo "### INFO: TOTAL_SVU_ACTIONS               : ${TOTAL_SVU_ACTIONS}"
echo ""

cat /tmp/paypal_requests.out| egrep -v "^$" | sed "s/	//g" 		>/tmp/paypal_requests.fmt.out
cat /tmp/action_id_2242.out| egrep -v "^$" | sed "s/	//g" 		>/tmp/action_id_2242.fmt.out
cat /tmp/paypal_ipn_sns_requests.out| egrep -v "^$" | sed "s/	//g" 	>/tmp/paypal_ipn_sns_requests.fmt.out
cat /tmp/paypal_ipn_s3_logs.out| egrep -v "^$" | sed "s/	//g" 	>/tmp/paypal_ipn_s3_logs.fmt.out

if [[ $( cat /tmp/paypal_requests.fmt.out | egrep "ORA" | wc -l ) -ge 1 ]] || [[ $( cat /tmp/action_id_2242.fmt.out | egrep "ORA" | wc -l ) -ge 1 ]]; then
	echo "Error: ORACLE errors found..."
	echo "<html><body><h3><br><br>Pls check ORACLE errors found...<br></h3>" 						>${RPT_FILE}
	echo "<font color="red">$( cat /tmp/paypal_requests.fmt.out /tmp/action_id_2242.fmt.out | egrep ORA )</font><br><br></body></html>" 	>>${RPT_FILE}
	#alarm_flag=2
else
	#
	# SNS topic
	#
	echo "<table>"  									                >${RPT_FILE}
	echo "<h3 style=\"blue\"><br><br>Report on SNS Topics Success/Failure Count<br></h3>"         		>>${RPT_FILE}
	echo "<tr bgcolor="yellow"><th>SNS Topics Status</th><th>Count</th></tr>"	                        >>${RPT_FILE}
	cat /tmp/paypal_ipn_sns_requests.fmt.out | while read line
	do
		col1=$( echo "${line}" | awk -F',' '{print $1}' )
		col2=$( echo "${line}" | awk -F',' '{print $2}' )
		echo "<tr><td>${col1}</td><td>${col2}</td></tr>"						>>${RPT_FILE}
	done	
	echo "</table>"												>>${RPT_FILE}
	#
	# S3 logs
	#   
	echo "<table>"  									>>${RPT_FILE}
	echo "<h3 style=\"blue\"><br><br>Report on Success/Errored requests from s3 <br></h3>"         		>>${RPT_FILE}
	echo "<tr bgcolor="yellow"><th>Total Requests</th><th>Count</th></tr>"	                        >>${RPT_FILE}
	cat /tmp/paypal_ipn_s3_logs.fmt.out | while read line
	do
		col1=$( echo "${line}" | awk -F',' '{print $1}' )
		col2=$( echo "${line}" | awk -F',' '{print $2}' )
		echo "<tr><td>${col1}</td><td>${col2}</td></tr>"						>>${RPT_FILE}
	done	
	echo "</table>"												>>${RPT_FILE}
	#
	# OBI transactions
	# 
	echo "<table>"  									>>${RPT_FILE}
	echo "<h3 style=\"blue\"><br><br>Report on Paypal Billing Agreement Cancels and Total Requests<br></h3>"        >>${RPT_FILE}
	echo "<tr bgcolor="yellow"><th>Name</th><th>Total Count</th></tr>"	                                        >>${RPT_FILE}
	cat /tmp/paypal_requests.fmt.out | while read line
	do
		col1=$( echo "${line}" | awk -F',' '{print $2}' )
		col2=$( echo "${line}" | awk -F',' '{print $3}' )
		echo "<tr><td>${col1}</td><td>${col2}</td></tr>"						>>${RPT_FILE}
	done	
	echo "</table>"												>>${RPT_FILE}
	#
	# SVU actions
	#   
	echo "<table>"  							                                >>${RPT_FILE}
	echo "<h3 style=\"blue\"><br><br>Report on SVU actions for paypal billing agreement cancel<br></h3>"         				>>${RPT_FILE}
	echo "<tr bgcolor="yellow"><th>Action Id</th><th>Count</th></tr>"	                                >>${RPT_FILE}
	cat /tmp/action_id_2242.fmt.out | while read line
	do
		col1=$( echo "${line}" | awk -F',' '{print $1}' )
		col2=$( echo "${line}" | awk -F',' '{print $2}' )
		echo "<tr><td>${col1}</td><td>${col2}</td></tr>"						>>${RPT_FILE}
	done	
	echo "</table>"												>>${RPT_FILE}
	
fi


FROM_EMAIL=${fromEmail}
RPT_BODY=${RPT_FILE}

if [[ ${alarm_flag} -eq 2 ]]; then
	RPT_SUBJ="Error : Paypal IPN Report for ${yest_dt}"
	TO_EMAIL=${toEmailDev}
	# send email notification
	email_report_func
	exit 1
else
	RPT_SUBJ="Paypal IPN Report for ${yest_dt}"
	TO_EMAIL=${toEmail}
	# send email notification
	email_report_func
fi

	rm -f ${RPT_FILE}		2>/dev/null

else
	echo "Usage: <script_name> <dbuser> <dbpassword>"
fi
