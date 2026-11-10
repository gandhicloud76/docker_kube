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
toEmail="jagadeesh.aluri@yahooinc.com,ritu.naikwadi@yahooinc.com,anil.dalli@yahooinc.com"
toEmailDev="anil.dalli@yahooinc.com"
#toEmail="anil.dalli@yahooinc.com"
#toEmailDev="anil.dalli@yahooinc.com"


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
# the SQLs to get total subscripts for each SKU where product name is UI_OMP_CART_SKU

sqlplus -S ${dbUser}/"${dbPass}"@'(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-obiardb2.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021))(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-obiardb1.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021)))(CONNECT_DATA=(SERVICE_NAME=OBIAR)))' >/tmp/product-subscription-count.out 2>&1 <<XXX
SET head off
SET feedback off
SET linesize 2000
SET colsep ,
select b.value, count(distinct a.offer_subscription_id) 
from sub_t a,	sub_provdata_t b 
where 
a.subscription_id = b.subscription_id 
and a.offer_id ='1005019' 
and b.name = 'UI_OMP_CART_SKU' 
and a.created_dt >to_date('2020-11-19 20:59:59','yyyy-mm-dd hh24:mi:ss') 
group by b.value;
exit;
XXX

cat /tmp/product-subscription-count.out | egrep -v "^$" | sed "s/ //g" >/tmp/product-subscription-count.fmt.out

if [ -s /tmp/product-subscription-count.fmt.out ]; then
	if [ $( cat /tmp/product-subscription-count.fmt.out | egrep "ORA" | wc -l ) -ge 1 ]; then
		echo "Error: ORACLE errors found..."
		echo "<html><body><h3><br><br>Pls check ORACLE errors found...<br></h3>" 					>/tmp/product-subscription-count.rpt.${cts}.html
		echo "<font color="red">$( cat /tmp/product-subscription-count.fmt.out | egrep ORA )</font><br><br></body></html>" 	>>/tmp/product-subscription-count.rpt.${cts}.html
		alarm_flag=2
	else

		echo "<html><body><table style=\"width:60%\">"                                      >/tmp/product-subscription-count.rpt.${cts}.html
		echo "<tr bgcolor="lightgrey" style=color:blue><th>SKU</th><th>Total Subscriptions</th></tr>"	>>/tmp/product-subscription-count.rpt.${cts}.html
			
		echo "alarm_flag=$alarm_flag"
		while read line
		do
			product=$( echo ${line} | awk -F"," '{print $1}' )
			total_subscriptions=$( echo ${line} | awk -F"," '{print $2}' )

			echo "<tr style=color:blue><td>${product}</td><td>${total_subscriptions}</td></tr>"	>>/tmp/product-subscription-count.rpt.${cts}.html
		done </tmp/product-subscription-count.fmt.out
		
		echo "<br><br>Note: Starting Date: Nov 19th 4 pm EST<br><br>" 		                >>/tmp/product-subscription-count.rpt.${cts}.html
		echo "</table></body></html>"								>>/tmp/product-subscription-count.rpt.${cts}.html
	fi
fi

FROM_EMAIL=${fromEmail}
RPT_BODY=/tmp/product-subscription-count.rpt.${cts}.html
RPT_SUBJ="test"
TO_EMAIL=${toEmail}

if [ ${alarm_flag} -eq 2 ]; then
	RPT_SUBJ="Failed : Product (UI_OMP_CART_SKU) Total Subscription : ${cts}"
	TO_EMAIL=${toEmailDev}
	# send email notification
	email_report_func
else
	RPT_SUBJ="Product (UI_OMP_CART_SKU) Total Subscription : ${cts}"
	TO_EMAIL=${toEmail}
	# send email notification
	email_report_func
fi

else
echo "Usage: <script_name> <dbuser> <dbpassword>"
fi

rm -f /tmp/product-subscription-count.rpt.${cts}.html		2>/dev/null

echo "###########: End"
