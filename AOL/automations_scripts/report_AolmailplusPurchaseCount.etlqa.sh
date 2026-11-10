#!/bin/sh

if [[ $# -eq 2 ]]; then

scriptName=$0
dbUser=$1
dbPass=$2
runDt=$( date '+%Y-%m-%d' )
cts=$( date '+%Y%m%d-%H%M' )
RPT_FILE="/tmp/aolmailplus_purchase_count.rpt.${cts}.html"
fromEmail="do-not-reply@yahoo.net"
alarm_flag=0
hostName=$( hostname )
toEmail="anil.dalli@yahooinc.com,gandhi.srinivasan@yahooinc.com,karthik.bheemanadula@yahooinc.com,shilpa.vontikommu@yahooinc.com,kumar.h@yahooinc.com,jagadeesh.aluri@yahooinc.com,uma.pandey@yahooinc.com,amukherj@yahooinc.com,aol.app.dev@yahooinc.com"
#toEmail="anil.dalli@yahooinc.com"
toEmailDev="anil.dalli@yahooinc.com,karthik.bheemanadula@yahooinc.com,gandhi.srinivasan@yahooinc.com"
# Fetch OpenAI API Key from AWS Parameter Store
OPENAI_API_KEY=$(aws ssm get-parameter --name "/env/OPENAI_API_KEY" --with-decryption --query "Parameter.Value" --output text)
PROJECT_DIR=$(dirname $0)

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
# the SQLs to get aolmailplus purchase count

sqlplus -S ${dbUser}/"${dbPass}"@'(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-obiardb2.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021))(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-obiardb1.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021)))(CONNECT_DATA=(SERVICE_NAME=OBIAR)))' >/tmp/aolmailplus_purchase_count.out 2>&1 <<XXX
SET head off
SET feedback off
SET linesize 2000
SET COLSEP '|'
select 
  offer_id,
  product_name,
  count(*) as count
from 
  sub_t s,
  SUB_PROVDATA_T sp
where 
  s.OFFER_ID in (1004863,1004865,1004867,1004869) and 
  s.SUBSCRIPTION_ID=sp.SUBSCRIPTION_ID(+) and 
  sp.NAME(+)='TEST_PURCHASE' and 
  s.CREATED_DT>to_date('2023-12-20 23:59:59','yyyy-mm-dd hh24:mi:ss') and 
  sp.name is null and 
  s.status=1 
group by 
  GROUPING SETS((offer_id,product_name),())
;
exit;
XXX

cat /tmp/aolmailplus_purchase_count.out| egrep -v "^$" | sed "s/	//g" >/tmp/aolmailplus_purchase_count.fmt.out

if [[ -s /tmp/aolmailplus_purchase_count.fmt.out ]]; then
	if [[ $( cat /tmp/aolmailplus_purchase_count.fmt.out | egrep "ORA" | wc -l ) -ge 1 ]]; then
		echo "Error: ORACLE errors found..."
		echo "<html><body><h3><br><br>Pls check ORACLE errors found...<br></h3>" 						>${RPT_FILE}
		echo "<font color="red">$( cat /tmp/aolmailplus_purchase_count.fmt.out | egrep ORA )</font><br><br></body></html>" 	>>${RPT_FILE}
		alarm_flag=2
	else

		echo "'<table style=\"width:60%\">"  							>${RPT_FILE}
		echo "<h3><br><br>AOLMAILPLUS Purchase Count Daily Report<br></h3>"         >>${RPT_FILE}
		echo "<tr bgcolor="lightgrey"><th>OFFER ID</th><th>PRODUCT NAME</th><th>COUNT</th></tr>"	>>${RPT_FILE}

		cat /tmp/aolmailplus_purchase_count.fmt.out | while read line
		do
			col1=$( echo "${line}" | awk -F'|' '{print $1}' )
			col2=$( echo "${line}" | awk -F'|' '{print $2}' )
			col3=$( echo "${line}" | awk -F'|' '{print $3}' )
			echo "<tr><td>${col1}</td><td>${col2}</td><td>${col3}</td></tr>"	>>${RPT_FILE}
		done	
		echo "</table>'"						>>${RPT_FILE}

		sqlite3 ${PROJECT_DIR}/mydata.db <<EOF
        CREATE TABLE IF NOT EXISTS aolmailplus(run_dt TEXT, text TEXT);
		DELETE FROM aolmailplus WHERE run_dt = '${runDt}';
        INSERT INTO aolmailplus(run_dt, text) VALUES('${runDt}', $(cat ${RPT_FILE}));
EOF

		last_week=$(date -d "-7 days" '+%Y-%m-%d')
		last_week_sales_data=$(sqlite3 ${PROJECT_DIR}/mydata.db "SELECT text FROM aolmailplus WHERE run_dt = '${last_week}'")
		today_sales_data=$(sqlite3 ${PROJECT_DIR}/mydata.db "SELECT text FROM aolmailplus WHERE run_dt = '${runDt}'")

		if [[ -z ${last_week_sales_data} ]] || [[ -z ${today_sales_data} ]]; then
			echo "Error: No data found for last_week or today"
			alarm_flag=2
		fi

		system_prompt="You are a helpful and cheerful person working in marketing. You would like to celebrate sales milestones by sending celebration emails, which inspires and congratulates the team. Response must be in html inside <div> only and start with <div> , which can be attached inline of email. Also style should be in body only.if no milestone event between last week to today's numbers, keep response as is"
		user_prompt="below you can see Last Week's email of numbers and Today's email. if today's number surpassed a milestone, decorate the today's email with celebration animation. provide email friendly decorated message only for Today's email. Also mention the numerical milestone for total number of Subscriptions. like surpassing 1k,2k, 3k.. registration milestones. if no milestone event between last week to today's numbers, keep response as is.\n\nLast Week's email:\n\n${last_week_sales_data}\n\nToday's email:\n\n${today_sales_data}"

		# Prepare JSON payload for OpenAI API
		json_payload=$(jq -n \
						--arg system_prompt "$system_prompt" \
						--arg user_prompt "$user_prompt" \
						'{
							"model": "gpt-4",
							"messages": [
							{
								"role": "system",
								"content": $system_prompt
							},
							{
								"role": "user",
								"content": $user_prompt
							}
							],
							"temperature": 1,
							"max_tokens": 1002,
							"top_p": 1,
							"frequency_penalty": 0,
							"presence_penalty": 0
						}')

		email_content=$(curl -s https://api.openai.com/v1/chat/completions \
		-H "Content-Type: application/json" \
		-H "Authorization: Bearer $OPENAI_API_KEY" \
		-d "$json_payload")

		email_content=$(echo ${email_content} | jq -r '.choices[0].message.content')

		# Validate email_content to start with <div>
		if [[ ${email_content:0:4} != "<div" ]]; then
			echo "Error: Invalid email content. Response must start with <div>"
			alarm_flag=2
		fi

		# Validate email_content has AOLMAILPLUS Purchase Count.
		#if [[ ${email_content} != *"AOLMAILPLUS Purchase Count"* ]]; then
		#	echo "Error: Invalid email content. Response must have AOLMAILPLUS Purchase Count"
		#	alarm_flag=2
		#fi

		# Validate email_content has <table>
		if [[ ${email_content} != *"<table"* ]]; then
			echo "Error: Invalid email content. Response must have <table>"
			alarm_flag=2
		fi


		echo "Generated email content: ${email_content}"
		echo "${email_content}" > ${RPT_FILE}

		echo "###########: End of OpenAI call"



	fi

	FROM_EMAIL=${fromEmail}
	RPT_BODY=${RPT_FILE}

	if [[ ${alarm_flag} -eq 2 ]]; then
		RPT_SUBJ="Error : AOLMAILPLUS Purchase Count Daily Report : ${cts}"
		TO_EMAIL=${toEmailDev}
		# send email notification
		email_report_func
		exit 1
	else 
		RPT_SUBJ="AOLMAILPLUS Purchase Count Daily Report : ${cts}"
		TO_EMAIL=${toEmail}
		# send email notification
		email_report_func
	fi

		rm -f ${RPT_FILE}		2>/dev/null

		echo "###########: End"
fi



else
	echo "Usage: <script_name> <dbuser> <dbpassword>"
fi
