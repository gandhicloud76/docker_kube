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


#toEmail="anil.dalli@yahooinc.com"
toEmail="v.jayaraman@yahooinc.com,anil.dalli@yahooinc.com"
toEmailDev="anil.dalli@yahooinc.com"


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
# the SQL to get count of YF promo code for social media

sqlplus -S "${dbUser}"/"${dbPass}"@'(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-obiardb2.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021))(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-obiardb1.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021)))(CONNECT_DATA=(SERVICE_NAME=OBIAR)))' >/tmp/mp_switch_errors.guids.out 2>&1 <<XXX
SET head off
SET feedback off
select distinct luid from sub_switch_t where trunc(switch_dt) = trunc(sysdate) and event_source like 'MAILP%' and status='ERROR';
exit;
XXX

cat /tmp/mp_switch_errors.guids.out | egrep -v "^$" | sed "s/ //g" >/tmp/mp_switch_errors.guids.fmt.out

if [ -s /tmp/mp_switch_errors.guids.fmt.out ]; then
	if [ $( cat /tmp/mp_switch_errors.guids.fmt.out | egrep "ORA" | wc -l ) -ge 1 ]; then
		echo "Error: ORACLE errors found..."
		echo "<html><body><h3><br><br>Pls check ORACLE errors found...<br></h3>" 					>/tmp/mp_switch_errors.guids.rpt.${cts}.html
		echo "<font color="red">$( cat /tmp/mp_switch_errors.guids.fmt.out | egrep ORA )</font><br><br></body></html>" 	>>/tmp/mp_switch_errors.guids.rpt.${cts}.html
		alarm_flag=2
	else

		echo "<html><body><table style=\"width:60%\">"                                      		>/tmp/mp_switch_errors.guids.rpt.${cts}.html

		if [ -s /tmp/mp_switch_errors.guids.fmt.out ]; then
			MAILPLUS_SWITCH_ERRORS_COUNT=$( cat /tmp/mp_switch_errors.guids.fmt.out | wc -l )
		else
			MAILPLUS_SWITCH_ERRORS_COUNT=0
		fi

		if [ ${MAILPLUS_SWITCH_ERRORS_COUNT} -gt 0 ]; then
			cat /tmp/mp_switch_errors.guids.fmt.out | while read guid
			do
				echo "<tr> <font size=\"3\" color=\"blue\">${guid}</font></tr>"	>>/tmp/mp_switch_errors.guids.rpt.${cts}.html
			done	
		else
			echo "<tr><font size=\"3\" color=\"blue\">no guids found</font></tr>"	>>/tmp/mp_switch_errors.guids.rpt.${cts}.html
		fi
		toEmail="${toEmail}"
		alarm_flag=1
		
		echo "</table></body></html>"						>>/tmp/mp_switch_errors.guids.rpt.${cts}.html
	fi
fi

FROM_EMAIL=${fromEmail}
RPT_BODY=/tmp/mp_switch_errors.guids.rpt.${cts}.html
RPT_SUBJ="test"
TO_EMAIL=${toEmail}

if [ ${alarm_flag} -eq 2 ]; then
	RPT_SUBJ="Error : MailPlus Switch Errors Daily Report : ${cts}"
	TO_EMAIL=${toEmailDev}
	# send email notification
	email_report_func
	exit 1
elif [ ${alarm_flag} -eq 1 ]; then
	RPT_SUBJ="MailPlus Switch Errors Daily Report [number of GUIDs found # ${MAILPLUS_SWITCH_ERRORS_COUNT}] : ${cts}"
	TO_EMAIL=${toEmail}
	# send email notification
	email_report_func
else
	#echo "Info: Do not send email"
	RPT_SUBJ="IGNORE: MailPlus Switch Errors Daily Report [0 GUIDs] : ${cts}"
	TO_EMAIL=${toEmailDev}
	# send email notification
	#email_report_func
fi

else
echo "Usage: <script_name> <dbuser> <dbpassword>"
fi

rm -f /tmp/mp_switch_errors.guids.rpt.${cts}.html	2>/dev/null

echo "###########: End"
