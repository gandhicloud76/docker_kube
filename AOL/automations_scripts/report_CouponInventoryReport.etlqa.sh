#!/bin/sh

if [ $# -eq 2 ]; then

scriptName=$0
dbUser=$1
dbPass=$2
runDt=$( date '+%Y-%m-%d' )
cts=$( date '+%Y%m%d-%H%M' )
RPT_FILE="/tmp/coupon_inventory_report.rpt.${cts}.html"
fromEmail="do-not-reply@yahoo.net"
alarm_flag=0
hostName=$( hostname )
toEmail="anil.dalli@yahooinc.com,shilpa.vontikommu@yahooinc.com,jagadeesh.aluri@yahooinc.com,scott.dorfman@yahooinc.com"
#toEmail="gandhi.srinivasan@yahooinc.com"
toEmailDev="anil.dalli@yahooinc.com,gandhi.srinivasan@yahooinc.com,karthik.bheemanadula@yahooinc.com"

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
# the SQLs to get Coupon Inventory Report

sqlplus -S ${dbUser}/"${dbPass}"@'(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-obiardb2.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021))(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-obiardb1.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021)))(CONNECT_DATA=(SERVICE_NAME=OBIAR)))' >/tmp/coupon_inventory_report.out 2>&1 <<XXX
SET head off
SET feedback off
SET linesize 2000
SET COLSEP '|'
select coupon_sku,count(*) from prm_coupon_uniq where status='NEW' and valid_until_dt>sysdate-30 and 
coupon_sku in (select coupon_sku from prm_coupon_batch where status='NEW' and 
coupon_sku in ('AARPMVP','REST25','REDBOX1','MRDTHMAGZN1','ESTATEPLAN')) 
group by coupon_sku;

exit;
XXX

sqlplus -S ${dbUser}/"${dbPass}"@'(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-obiardb2.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021))(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-obiardb1.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021)))(CONNECT_DATA=(SERVICE_NAME=OBIAR)))' >/tmp/assigned_count.out 2>&1 <<YYY
SET head off
SET feedback off
SET linesize 2000
SET COLSEP '|'
select coupon_sku,count(*) from prm_coupon_uniq where status='ASSIGNED' and assigned_dt>sysdate-1 and 
coupon_sku in ('AARPMVP','REST25','REDBOX1','MRDTHMAGZN1','ESTATEPLAN') 
group by coupon_sku;

exit;
YYY


cat /tmp/coupon_inventory_report.out| egrep -v "^$" | sed "s/	//g" >/tmp/coupon_inventory_report.fmt.out
cat /tmp/assigned_count.out| egrep -v "^$" | sed "s/	//g" >/tmp/assigned_count.fmt.out

if [[ $( cat /tmp/coupon_inventory_report.fmt.out | egrep "ORA" | wc -l ) -ge 1 ]] || [[ $( cat /tmp/assigned_count.fmt.out | egrep "ORA" | wc -l ) -ge 1 ]]; then
	echo "Error: ORACLE errors found..."
	echo "<html><body><h3><br><br>Pls check ORACLE errors found...<br></h3>" 						>${RPT_FILE}
	echo "<font color="red">$( cat /tmp/coupon_inventory_report.fmt.out /tmp/assigned_count.fmt.out | egrep ORA )</font><br><br></body></html>" 	>>${RPT_FILE}
	alarm_flag=2
else

	echo "<table style=\"width:60%\">"  																	>${RPT_FILE}
	echo "<h3><br><br>Coupon Inventory Report<br></h3>"         					>>${RPT_FILE}
	echo "<tr bgcolor="lightgrey"><th>COUPON_SKU</th><th>COUNT</th></tr>"	>>${RPT_FILE}

	cat /tmp/coupon_inventory_report.fmt.out | while read line
	do
		col1=$( echo "${line}" | awk -F'|' '{print $1}' )
		col2=$( echo "${line}" | awk -F'|' '{print $2}' )
		echo "<tr><td>${col1}</td><td>${col2}</td></tr>"										>>${RPT_FILE}
	done	
	echo "</table>"																											>>${RPT_FILE}
	echo "<br><br><table style=\"width:60%\">"  													>>${RPT_FILE}
	echo "<h3><br><br>Assigned Count<br></h3>"         										>>${RPT_FILE}
	echo "<tr bgcolor="lightgrey"><th>COUPON_SKU</th><th>COUNT</th></tr>"	>>${RPT_FILE}

	cat /tmp/assigned_count.fmt.out | while read line
	do
		col1=$( echo "${line}" | awk -F'|' '{print $1}' )
		col2=$( echo "${line}" | awk -F'|' '{print $2}' )
		echo "<tr><td>${col1}</td><td>${col2}</td></tr>"										>>${RPT_FILE}
	done	
	echo "</table>"																											>>${RPT_FILE}
fi
FROM_EMAIL=${fromEmail}
RPT_BODY=${RPT_FILE}

if [[ ${alarm_flag} -eq 2 ]]; then
	RPT_SUBJ="Error : Coupon Inventory Report : ${cts}"
	TO_EMAIL=${toEmailDev}
	# send email notification
	email_report_func
	exit 1
else
	RPT_SUBJ="Coupon Inventory Report : ${cts}"
	TO_EMAIL=${toEmail}
	# send email notification
	email_report_func
fi

	rm -f ${RPT_FILE}		2>/dev/null

else
	echo "Usage: <script_name> <dbuser> <dbpassword>"
fi
