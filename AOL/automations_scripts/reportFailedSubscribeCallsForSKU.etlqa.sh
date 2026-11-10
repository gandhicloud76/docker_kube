#!/bin/sh
if [ $# -eq 2 ]; then
scriptName=$0
dbUser=$1
dbPass=$2
runDt=$( date '+%Y-%m-%d' )
fromEmail="do-not-reply@yahoo.net"
alarm_flag1=0
alarm_flag2=0
hostName=$( hostname )
toEmail="obi-vendor-alerts@yahooinc.com,anil.dalli@yahooinc.com"
#toEmail="anil.dalli@yahooinc.com"
toEmailDev="gandhi.srinviasan@yahooinc.com,anil.dalli@yahooinc.com"
thresholdPct=30
echo "###########: Start script ${scriptName} is running on host ${hostName}"
. /home/ec2-user/.profile
#cleanup tmp files from previous run
rm -f /tmp/failed-subscribe-calls* 2>/dev/null
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
# the SQLs to get the failed subscribe calls for each SKU in past 1 day window
sqlplus -S ${dbUser}/"${dbPass}"@'(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-bpsprd1-new.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021))(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-bpsprd1.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021)))(CONNECT_DATA=(SERVICE_NAME=BPS_PRD)))' >/tmp/failed-subscribe-calls1.out 2>&1 <<XXX
SET head off
SET feedback off
SET linesize 2000
SET PAGESIZE 0
SET colsep ,
select 
  tvl.Product_SKU,
  SUBSTR(tvl.end_point,INSTR(tvl.end_point, '/',8)+1,(INSTR(tvl.end_point, '/', 9)-INSTR(tvl.end_point, '/',8)-1)) as Domain_name,
  sum(case when (tvl.HTTP_STATUS not between 200 and 299) or (tvl.resp_desc in ('Subscribe failed','Redeem token failed')) then 1 else 0 end) as Failures,
  sum(case when tvl.HTTP_STATUS between 200 and 299 and tvl.Resp_time > 30000 then 1 else 0 end) as Slow_Response,count(1) as Total,
  ROUND(((sum(case when (tvl.HTTP_STATUS not between 200 and 299)or (tvl.resp_desc in ('Subscribe failed','Redeem token failed')) then 1 else 0 end)+sum(case when tvl.HTTP_STATUS between 200 and 299 and tvl.Resp_time > 30000 then 1 else 0 end))/count(1))*100,0) as Percentage
from 
  trans_vendor_log tvl
where 
  tvl.ACTION = 'SUBSCRIBE' and tvl.created_dt > sysdate-1
group by 
  tvl.Product_SKU,
  SUBSTR(tvl.end_point,INSTR(tvl.end_point, '/',8)+1,(INSTR(tvl.end_point, '/', 9)-INSTR(tvl.end_point, '/',8)-1))
having 
  sum(case when tvl.HTTP_STATUS not between 200 and 299 then 1 else 0 end) > 0
  or sum(case when tvl.HTTP_STATUS between 200 and 299 and tvl.Resp_time > 30000 then 1 else 0 end) >0
  or sum(case when tvl.resp_desc in ('Subscribe failed','Redeem token failed') then 1 else 0 end) >0
order by 
  failures desc,
  slow_response desc,
  tvl.Product_SKU;
exit;
XXX
cat /tmp/failed-subscribe-calls1.out | egrep -v "^$" | sort -u >/tmp/failed-subscribe-calls1.uniq.out
if [ -s /tmp/failed-subscribe-calls1.uniq.out ]; then
	if [ $( cat /tmp/failed-subscribe-calls1.uniq.out | egrep "ORA" | wc -l ) -ge 1 ]; then
		echo "Error: ORACLE errors found..."
		echo "<h3><br><br>Pls check ORACLE errors found...<br></h3>" 					                    >>/tmp/failed-subscribe-calls1.rpt.${runDt}.html
		echo "<font color="red">$( cat /tmp/failed-subscribe-calls1.uniq.out | egrep ORA )</font><br><br>" 	>>/tmp/failed-subscribe-calls1.rpt.${runDt}.html
		alarm_flag1=2
	else
		echo "<table style=\"width:60%\">"									>>/tmp/failed-subscribe-calls1.rpt.${runDt}.html
		echo "<tr bgcolor="lightblue"><th>SKU</th><th>Domain Name</th><th>Failures</th><th>Slow Response</th><th>Total</th><th>Percentage</th></tr>"	>>/tmp/failed-subscribe-calls1.rpt.${runDt}.html
		echo "alarm_flag1=$alarm_flag1"
		while read line
		do
			sku=$( echo ${line} | awk -F"," '{print $1}' )
			Domain_name=$( echo ${line} | awk -F"," '{print $2}' )
			failures=$( echo ${line} | awk -F"," '{print $3}' )
			slow_response=$( echo ${line} | awk -F"," '{print $4}' )
			total=$( echo ${line} | awk -F"," '{print $5}' )
            percentage=$( echo ${line} | awk -F"," '{print $6}' )
			if [ ${percentage} -gt ${thresholdPct} ]; then
				alarm_flag1=1
				echo  "<tr style=color:red><td>${sku}</td><td>${Domain_name}</td><td>${failures}</td><td>${slow_response}</td><td>${total}</td><td>${percentage}</td></tr"   >>/tmp/failed-subscribe-calls1.rpt.${runDt}.html
			else
				echo  "<tr style=color:red><td>${sku}</td><td>${Domain_name}</td><td>${failures}</td><td>${slow_response}</td><td>${total}</td><td>${percentage}</td></tr>"  >>/tmp/failed-subscribe-calls1.rpt.${runDt}.html
			fi
		done </tmp/failed-subscribe-calls1.uniq.out
		echo "</table>"											>>/tmp/failed-subscribe-calls1.rpt.${runDt}.html
	fi
fi
# the SQLs to get the reasons for failed subscribe calls for each SKU in past 1 day window
sqlplus -S ${dbUser}/"${dbPass}"@'(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-bpsprd1-new.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021))(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-bpsprd1.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021)))(CONNECT_DATA=(SERVICE_NAME=BPS_PRD)))' >/tmp/failed-subscribe-calls2.out 2>&1 <<XXX
SET head off
set pages 0
SET feedback off
SET linesize 5000
SET PAGESIZE 0
SET colsep ,
select product_SKU,resp_desc, count(*) as Count
from trans_vendor_log
where ACTION = 'SUBSCRIBE' and 
created_dt > sysdate-1 and
((HTTP_STATUS not between 200 and 299) or (resp_desc in ('Subscribe failed','Redeem token failed')))
group by product_SKU,resp_desc;
exit;
XXX
cat /tmp/failed-subscribe-calls2.out | egrep -v "^$" | sort -u >/tmp/failed-subscribe-calls2.uniq.out
if [ -s /tmp/failed-subscribe-calls2.uniq.out ]; then
	if [ $( cat /tmp/failed-subscribe-calls2.uniq.out | egrep "ORA" | wc -l ) -ge 1 ]; then
		echo "Error: ORACLE errors found..."
		echo "<h3><br><br>Pls check ORACLE errors found...<br></h3>" 					>>/tmp/failed-subscribe-calls2.rpt.${runDt}.html
		echo "<font color="red">$( cat /tmp/failed-subscribe-calls2.uniq.out | egrep ORA )</font><br><br>" 	>>/tmp/failed-subscribe-calls2.rpt.${runDt}.html
		alarm_flag2=2
	else
		echo "<html><body><table style=\"width:60%\">"									>>/tmp/failed-subscribe-calls2.rpt.${runDt}.html
		echo "<tr bgcolor="lightblue"><th>SKU</th><th>Reason</th><th>Count</th></tr>"	>>/tmp/failed-subscribe-calls2.rpt.${runDt}.html
		echo "alarm_flag2=$alarm_flag2"
		while read line
		do
			SKU=$( echo ${line} | awk -F"," '{print $1}' )
			Reason=$( echo ${line} | awk -F"," '{print $2}' )
			Count=$( echo ${line} | awk -F"," '{print $3}' )
            echo  "<tr style=color:><td>${SKU}</td><td>${Reason}</td><td>${Count}</td></tr>"		>>/tmp/failed-subscribe-calls2.rpt.${runDt}.html
		done </tmp/failed-subscribe-calls2.uniq.out
		echo "</table>"											>>/tmp/failed-subscribe-calls2.rpt.${runDt}.html
	fi
fi

if [[ -s /tmp/failed-subscribe-calls1.rpt.${runDt}.html ]] && [[ -s /tmp/failed-subscribe-calls2.rpt.${runDt}.html ]]; then
	echo "<html><body>"                                 		>/tmp/failed-subscribe-calls.rpt.${runDt}.html     
	cat /tmp/failed-subscribe-calls1.rpt.${runDt}.html   		>>/tmp/failed-subscribe-calls.rpt.${runDt}.html
	echo "<br><h3><br><br> Failures by Reason <br></h3><br>"        >>/tmp/failed-subscribe-calls.rpt.${runDt}.html
	cat /tmp/failed-subscribe-calls2.rpt.${runDt}.html  		>>/tmp/failed-subscribe-calls.rpt.${runDt}.html  
	echo "</body></html>"                               		>>/tmp/failed-subscribe-calls.rpt.${runDt}.html  
else
	echo "<html><body>"                                 		>/tmp/failed-subscribe-calls.rpt.${runDt}.html
	echo "<br><h3><br><br>No Failures to report<br></h3><br>"       >>/tmp/failed-subscribe-calls.rpt.${runDt}.html
	echo "</body></html>"                               		>>/tmp/failed-subscribe-calls.rpt.${runDt}.html  

fi
FROM_EMAIL=${fromEmail}
RPT_BODY=/tmp/failed-subscribe-calls.rpt.${runDt}.html
RPT_SUBJ="test"
TO_EMAIL=${toEmail}
if [ ${alarm_flag1} -eq 1 ]; then
	RPT_SUBJ="FAILED-SUBSCRIBE-CALLS (exceeding threshold) : ${runDt}"
	TO_EMAIL=${toEmail}
	# send email notification
	email_report_func
elif [ ${alarm_flag1} -eq 2 ] || [ ${alarm_flag2} -eq 2 ]; then
	RPT_SUBJ="Failed : FAILED-SUBSCRIBE-CALLS : ${runDt}"
	TO_EMAIL=${toEmailDev}
	# send email notification
	email_report_func
else
	RPT_SUBJ="FAILED-SUBSCRIBE-CALLS (all good) : ${runDt}"
	TO_EMAIL=${toEmail}
	# send email notification
	email_report_func
	echo "###########: ${RPT_SUBJ}"
fi
else
echo "Usage: <script_name> <dbuser> <dbpassword>"
fi
rm -f /tmp/failed-subscribe-calls1.rpt.${runDt}.html		2>/dev/null
rm -f /tmp/failed-subscribe-calls2.rpt.${runDt}.html		2>/dev/null
echo "###########: End"
