#!/bin/sh

if [ $# -eq 2 ]; then

scriptName=$0
dbUser=$1
dbPass=$2
runDt=$( date '+%Y-%m-%d' )
cts=$( date '+%Y%m%d-%H%M' )
fromEmail="do-not-reply@yahoo.net"
alarm_flag=0
hostName=$( hostname )
toEmail="jagadeesh.aluri@yahooinc.com,pum.kim@yahooinc.com,shilpa.vontikommu@yahooinc.com,anil.dalli@yahooinc.com,gandhi.srinivasan@yahooinc.com,karthik,bheemanadula@yahooinc.com"
toEmailDev="anil.dalli@yahooinc.com,gandhi.srinivasan@yahooinc.com,karthik,bheemanadula@yahooinc.com"
#toEmail="anil.dalli@yahooinc.com,gandhi.srinivasan@yahooinc.com,karthik,bheemanadula@yahooinc.com"


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
Content-Type: multipart/mized;
 boundary="MAIL_BOUNDARY"
--MAIL_BOUNDARY
Content-Type: multipart/alternative;
 boundary="MAIL_BOUNDARY2"
--MAIL_BOUNDARY2
Content-Type: text/plain; charset=utf-8
${RPT_SUBJ}
--MAIL_BOUNDARY2
Content-Type: text/html; charset=utf-8
--OEF--
cat ${RPT_BODY}

cat << --OEF--
--OEF--
) |  /usr/sbin/sendmail -f "${FROM_EMAIL}" "${TO_EMAIL}"

}


# 
# the SQL is to get guids and amounts for which payments were stuck beyond  15 days’ window

sqlplus -S ${dbUser}/"${dbPass}"@'(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-obiardb2.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021))(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-obiardb1.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021)))(CONNECT_DATA=(SERVICE_NAME=OBIAR)))' >/tmp/pending-payments-beyond-fifteen-days.out 2>&1 <<XXX
SET head off
SET feedback off
SET linesize 2000
SET colsep ,
SELECT luid,sap_invoice_id,amount,created_dt 
FROM sap_mass_pay_item 
WHERE  
status = 'I' 
and created_dt<sysdate-15 
order by created_dt desc,amount desc;
exit;
XXX

cat /tmp/pending-payments-beyond-fifteen-days.out | egrep -v "^$" | sed "s/ //g" >/tmp/pending-payments-beyond-fifteen-days.fmt.out

if [ -s /tmp/pending-payments-beyond-fifteen-days.fmt.out ]; then
	if [ $( cat /tmp/pending-payments-beyond-fifteen-days.fmt.out | egrep "ORA" | wc -l ) -ge 1 ]; then
		echo "Error: ORACLE errors found..."
		echo "<html><body><h3><br><br>Pls check ORACLE errors found...<br></h3>" 					>/tmp/pending-payments-beyond-fifteen-days.rpt.${cts}.html
		echo "<font color="red">$( cat /tmp/pending-payments-beyond-fifteen-days.fmt.out | egrep ORA )</font><br><br></body></html>" 	>>/tmp/pending-payments-beyond-fifteen-days.rpt.${cts}.html
		alarm_flag=2
	else

		echo "<html><body><table style=\"width:60%\">"                                      >/tmp/pending-payments-beyond-fifteen-days.rpt.${cts}.html
		echo "<tr bgcolor="lightgrey" style=color:blue><th>GUID</th><th>Invoice ID</th><th>Amount</th><th>Date Created</th></tr>"	>>/tmp/pending-payments-beyond-fifteen-days.rpt.${cts}.html
			
		echo "alarm_flag=$alarm_flag"
		while read line
		do	
            		guid=$( echo ${line} | awk -F"," '{print $1}' )
			invoice_id=$( echo ${line} | awk -F"," '{print $2}' )
            		amount=$( echo ${line} | awk -F"," '{print $3}' )
			create_date=$( echo ${line} | awk -F"," '{print $4}' )

			echo "<tr style=color:blue><td>${guid}</td><td>${invoice_id}</td><td>${amount}</td><td>${create_date}</td></tr>"	>>/tmp/pending-payments-beyond-fifteen-days.rpt.${cts}.html
		done </tmp/pending-payments-beyond-fifteen-days.fmt.out
		
		echo "<br><br>Note: Pending Payments older than 15 days<br><br>" 		                >>/tmp/pending-payments-beyond-fifteen-days.rpt.${cts}.html
		echo "</table></body></html>"								>>/tmp/pending-payments-beyond-fifteen-days.rpt.${cts}.html
	fi
fi

FROM_EMAIL=${fromEmail}
RPT_BODY=/tmp/pending-payments-beyond-fifteen-days.rpt.${cts}.html
RPT_SUBJ="test"
TO_EMAIL=${toEmail}

if [ ${alarm_flag} -eq 2 ]; then
	RPT_SUBJ="Failed : Pending Payments older than 15 days : ${cts}"
	TO_EMAIL=${toEmailDev}
	# send email notification
	email_report_func
else
	RPT_SUBJ="Pending Payments older than 15 days : ${cts}"
	TO_EMAIL=${toEmail}
	# send email notification
	email_report_func
fi

else
echo "Usage: <script_name> <dbuser> <dbpassword>"
fi

rm -f /tmp/pending-payments-beyond-fifteen-days.rpt.${cts}.html		2>/dev/null

echo "###########: End"
