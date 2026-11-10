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
COUNTER=500
#toEmail="jagadeesh.aluri@yahooinc.com,pum.kim@yahooinc.com,shilpa.vontikommu@yahooinc.com,anil.dalli@yahooinc.com"
#toEmailDev="anil.dalli@yahooinc.com"

toEmail_level1="anil.dalli@yahooinc.com"
toEmail_level2="anil.dalli@yahooinc.com"
toEmail_level3="anil.dalli@yahooinc.com"
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

sqlplus -S "${dbUser}"/"${dbPass}"@'(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-obiardb2.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021))(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-obiardb1.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021)))(CONNECT_DATA=(SERVICE_NAME=OBIAR)))' >/tmp/yfPromoCount.out 2>&1 <<XXX
SET head off
SET feedback off
SELECT count(*) 
from prm_promo_usage 
where 
promo_code='VIP3MONS';
exit;
XXX

cat /tmp/yfPromoCount.out | egrep -v "^$" | sed "s/ //g" >/tmp/yfPromoCount.fmt.out

if [ -s /tmp/yfPromoCount.fmt.out ]; then
	if [ $( cat /tmp/yfPromoCount.fmt.out | egrep "ORA" | wc -l ) -ge 1 ]; then
		echo "Error: ORACLE errors found..."
		echo "<html><body><h3><br><br>Pls check ORACLE errors found...<br></h3>" 					>/tmp/yfPromoCount.rpt.${cts}.html
		echo "<font color="red">$( cat /tmp/yfPromoCount.fmt.out | egrep ORA )</font><br><br></body></html>" 	>>/tmp/yfPromoCount.rpt.${cts}.html
		alarm_flag=2
	else

		echo "<html><body><table style=\"width:60%\">"                                      		>/tmp/yfPromoCount.rpt.${cts}.html

		PROMO_COUNT=$( cat /tmp/yfPromoCount.fmt.out )
		echo "PROMO_COUNT: $PROMO_COUNT"

		PC_BATCH_NUM=$( echo "${PROMO_COUNT}/500" | bc )
		if [ ${PC_BATCH_NUM} -gt 0 ]; then
			if [ ! -f pc.${PC_BATCH_NUM}.done ]; then
				if [ ${PC_BATCH_NUM} -eq 40 ] || [ ${PC_BATCH_NUM} -eq 38 ] || [ ${PC_BATCH_NUM} -eq 36 ]; then
					echo "<tr bgcolor=\"#EBE9E9\"><th><font size=\"5\" color=\"red\">Yahoo Finance Social Media Promo Count : ${PROMO_COUNT}</font></th></tr>"	>>/tmp/yfPromoCount.rpt.${cts}.html
					toEmail="${toEmail_level1}"
					alarm_flag=1
				elif [ ${PC_BATCH_NUM} -eq 34 ] || [ ${PC_BATCH_NUM} -eq 30 ] || [ ${PC_BATCH_NUM} -eq 20 ]; then 
					echo "<tr bgcolor=\"#EBE9E9\"><th><font size=\"5\" color=\"blue\">Yahoo Finance Social Media Promo Count : ${PROMO_COUNT}</font></th></tr>"	>>/tmp/yfPromoCount.rpt.${cts}.html
					toEmail="${toEmail_level1}"
					alarm_flag=1
				elif [ ${PC_BATCH_NUM} -eq 10 ] || [ ${PC_BATCH_NUM} -eq 4 ] || [ ${PC_BATCH_NUM} -eq 1 ]; then
					echo "<tr bgcolor=\"#EBE9E9\"><th><font size=\"5\" color=\"blue\">Yahoo Finance Social Media Promo Count : ${PROMO_COUNT}</font></th></tr>"	>>/tmp/yfPromoCount.rpt.${cts}.html
					toEmail="${toEmail_level2}"
					alarm_flag=1
				else
					echo "<tr bgcolor=\"#EBE9E9\"><th><font size=\"5\" color=\"blue\">Yahoo Finance Social Media Promo Count : ${PROMO_COUNT}</font></th></tr>"	>>/tmp/yfPromoCount.rpt.${cts}.html
					toEmail="${toEmail_level3}"
					alarm_flag=1
				fi
			else
				echo "Info: Already notified"
			fi
		fi
		
		echo "</table></body></html>"						>>/tmp/yfPromoCount.rpt.${cts}.html
	fi
fi

FROM_EMAIL=${fromEmail}
RPT_BODY=/tmp/yfPromoCount.rpt.${cts}.html
RPT_SUBJ="test"
TO_EMAIL=${toEmail}

if [ ${alarm_flag} -eq 2 ]; then
	RPT_SUBJ="Error : Yahoo Finance Social Media Promo Count : ${cts}"
	TO_EMAIL=${toEmailDev}
	# send email notification
	email_report_func
	exit 1
elif [ ${alarm_flag} -eq 1 ]; then
	RPT_SUBJ="Yahoo Finance Social Media Promo Count [#${PROMO_COUNT}] : ${cts}"
	TO_EMAIL=${toEmail}
	# send email notification
	email_report_func
	touch pc.${PC_BATCH_NUM}.done
else
	echo "Info: Do not send email"
fi

else
echo "Usage: <script_name> <dbuser> <dbpassword>"
fi

rm -f /tmp/yfPromoCount.rpt.${cts}.html		2>/dev/null

echo "###########: End"
