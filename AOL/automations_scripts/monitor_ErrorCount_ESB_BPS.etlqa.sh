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
toEmail="durga.nemani@yahooinc.com,v.jayaraman@yahooinc.com,steve.fink@yahooinc.com,anil.dalli@yahooinc.com,sudhakar.gollapinni@yahooinc.com,jagadeesh.aluri@yahooinc.com,soujanya.vullam@yahooinc.com,sangeeta.bhatia@yahooinc.com,shilpa.vontikommu@yahooinc.com,gandhi.srinivasan@yahooinc.com"
#toEmail="anil.dalli@yahooinc.com,gandhi.srinivasan@yahooinc.com"
toEmailDev="anil.dalli@yahooinc.com,gandhi.srinivasan@yahooinc.com"

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
# the SQLs to get the errors count are prefixed by printing - Error Name, Threshold limit, Error check time span (last 1 hour, last N hours etc)
# e.g. "ABC ERRORS,100,last 1 hour"

sqlplus -S ${dbUser}/"${dbPass}"@'(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-bpsprd1-new.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021))(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-bpsprd1.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021)))(CONNECT_DATA=(SERVICE_NAME=BPS_PRD)))' >/tmp/esb-bps-error-count.out 2>&1 <<XXX
SET head off
SET feedback off
SET linesize 2000
select 'TRANSLOG ERRORS,10,last 1 hour,' || count(*) from obi_transaction_log where created_dt > (sysdate - 1/24) and (status_obi_code='OBI-1200' or status_obi_code='OBI-1300' or status_obi_code='PAYBWS-324' )
UNION
select 'READ API ERRORS,10,last 1 hour,' || count(*) from obi_read_api_log where created_dt > (sysdate - 1/24) and (status_obi_code='OBI-1200' or status_obi_code='OBI-1300')
UNION
select 'PAYMENT AUTH ERRORS,30,last 1 hour,' || count(*) from obi_payment_auth_log where created_dt > (sysdate - 1/24) and duration > 10000
UNION
select 'EPAY CERT/TIMEOUT ERROR,0,last 1 hour,' || count(*) from epay_transaction_log where created_dt > (sysdate - 1/24) and OBI_REQUEST_ID is not null and http_response_code is null
UNION
select 'EPAY AUTH ERROR,50,last 1 hour,' || count(*) from epay_transaction_log etl, obi_transaction_log otl where etl.OBI_REQUEST_ID=otl.TRANSACTION_ID and etl.created_dt > (sysdate - 1/24) and etl.http_response_code=412 and etl.response not like '%E4003%'
UNION
select 'EPAY ERROR 500,0,last 1 hour,' || count(*) from epay_transaction_log where created_dt > (sysdate - 1/24) and OBI_REQUEST_ID is not null and http_response_code=500
UNION
select 'EPAY ERROR 406,5,last 1 hour,' || count(*) from epay_transaction_log where created_dt > (sysdate - 1/24) and http_response_code=406 and response not like '%E6058%' and response not like '%E4008%' 
UNION
select 'EPAY CARD PURGED OR DENIEDLISTED,0,last 1 hour,' || count(*) from epay_transaction_log where created_dt > (sysdate - 1/24) and http_response_code=404 and merchant_id <>'yhoo'
UNION
select 'EPAY DUPLICATE REQUEST (multiple OSBs),10,last 1 hour,' || count(*) from epay_transaction_log where created_dt > (sysdate - 1/24) and http_response_code=400 and response not like '%E6044%'
UNION
select 'BILLING EVENT NOTIFICATIONS,0,last 1 hour,' || count(*) from daily_settlement_events_v1 where event_status = 'FAILED' and event_attempt >= 5 and event_startat > TO_TIMESTAMP(to_char(sysdate-1/24,'dd-mon-yy hh:mi:ss'))
UNION
select 'SUBSCRIPTION EVENT NOTIFICATIONS,0,last 1 hour,' || count(*) from event_subscription_status where event_status = 'FAILED' and event_attempt >= 5 and event_startat > TO_TIMESTAMP(to_char(sysdate-1/24,'dd-mon-yy hh:mi:ss'))
UNION
select 'CLEAR TEXT CREDIT CARD ERROR,0,last 1 hour,' || count(*) from obi_transaction_log where created_dt > (sysdate - 1/24) and status<>200 and status_obi_code='PAY-0053';
exit;
XXX

sqlplus -S ${dbUser}/"${dbPass}"@'(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-bpsprd1-new.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021))(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-bpsprd1.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021)))(CONNECT_DATA=(SERVICE_NAME=BPS_PRD)))' >/tmp/esb-bps-error-count.es_msg_delivery_state.out 2>&1 <<YYY
SET head off
SET feedback off
SET linesize 2000
-- EventService message delivery state
SELECT
    CASE WH.WEBHOOK_NAME
        WHEN 'PAYMENT' THEN 'Billing Event Notifications'
        WHEN 'SUBSCRIPTION' THEN 'Subscription Event Notifications'
        ELSE WH.WEBHOOK_NAME
    END || ',7,last 1 hour,' || count(M.MESSAGE_ID)
FROM OBI_WEBHOOKS WH
         LEFT JOIN  OBI_WEBHOOK_MESSAGES M ON WH.ID = M.WEBHOOK_ID
    AND M.MESSAGE_STATE = 'FAILED'
    AND MESSAGE_START_AT BETWEEN TRUNC(systimestamp-1.0/24, 'HH')
        AND CAST(TRUNC(systimestamp, 'HH') AS TIMESTAMP) - interval '0.000001' SECOND
GROUP BY WH.ID, WH.WEBHOOK_NAME, WH.EVENT_SOURCE, M.MESSAGE_STATE
ORDER BY WH.ID;
exit;
YYY

sqlplus -S ${dbUser}/"${dbPass}"@'(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-bpsprd1-new.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021))(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-bpsprd1.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021)))(CONNECT_DATA=(SERVICE_NAME=BPS_PRD)))' >/tmp/esb-bps-error-count.es_msg_queues_state.out 2>&1 <<ZZZ
SET head off
SET feedback off
SET linesize 2000
-- EventService queues state
WITH STATUSES (STATUS) AS (
    SELECT 'QUEUED' FROM DUAL UNION
    SELECT 'RUNNING' FROM DUAL UNION
    SELECT 'FAILED' FROM DUAL
)
SELECT 'PAYMENT,' || STATUSES.STATUS || ',0,last 1 hour,' || count(S.EVENT_ID)
FROM STATUSES
     LEFT JOIN DAILY_SETTLEMENT_EVENTS_V1 S ON STATUSES.STATUS = S.EVENT_STATUS
        AND SYS_EXTRACT_UTC(EVENT_STARTAT) BETWEEN TRUNC(systimestamp-1.0/24, 'HH')
            AND CAST(TRUNC(systimestamp, 'HH') AS TIMESTAMP) - interval '0.000001' SECOND
GROUP BY STATUSES.STATUS
UNION
SELECT 'SUBSCRIPTION,' || STATUSES.STATUS || ',0,last 1 hour,' || count(S.EVENT_ID)
FROM STATUSES
     LEFT JOIN EVENT_SUBSCRIPTION_STATUS S ON STATUSES.STATUS = S.EVENT_STATUS
        AND SYS_EXTRACT_UTC(EVENT_STARTAT) BETWEEN TRUNC(systimestamp-1.0/24, 'HH')
            AND CAST(TRUNC(systimestamp, 'HH') AS TIMESTAMP) - interval '0.000001' SECOND
GROUP BY STATUSES.STATUS
UNION
SELECT 'ASC,' || STATUSES.STATUS || ',0,last 1 hour,' || count(S.EVENT_ID)
FROM STATUSES
     LEFT JOIN ASC_RECORDS S ON STATUSES.STATUS = S.EVENT_STATUS
        AND SYS_EXTRACT_UTC(EVENT_STARTAT) BETWEEN TRUNC(systimestamp-1.0/24, 'HH')
            AND CAST(TRUNC(systimestamp, 'HH') AS TIMESTAMP) - interval '0.000001' SECOND
GROUP BY STATUSES.STATUS
UNION
SELECT 'EVENTS,' || STATUSES.STATUS || ',0,last 1 hour,' || count(S.EVENT_ID)
FROM STATUSES
     LEFT JOIN OBI_WEBHOOK_EVENTS S ON STATUSES.STATUS = S.EVENT_STATE
        AND SYS_EXTRACT_UTC(EVENT_TIMESTAMP) BETWEEN TRUNC(systimestamp-1.0/24, 'HH')
            AND CAST(TRUNC(systimestamp, 'HH') AS TIMESTAMP) - interval '0.000001' SECOND
GROUP BY STATUSES.STATUS
UNION
SELECT 'MESSAGES,' || STATUSES.STATUS || ',0,last 1 hour,' || count(S.EVENT_ID)
FROM STATUSES
     LEFT JOIN OBI_WEBHOOK_MESSAGES S ON STATUSES.STATUS = S.MESSAGE_STATE
        AND SYS_EXTRACT_UTC(MESSAGE_START_AT) BETWEEN TRUNC(systimestamp-1.0/24, 'HH')
            AND CAST(TRUNC(systimestamp, 'HH') AS TIMESTAMP) - interval '0.000001' SECOND
GROUP BY STATUSES.STATUS;
exit;
ZZZ

sqlplus -S ${dbUser}/"${dbPass}"@'(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-bpsprd1-new.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021))(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-bpsprd1.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021)))(CONNECT_DATA=(SERVICE_NAME=BPS_PRD)))' >/tmp/esb-bps-error-count.es_only_queued_state.out 2>&1 <<WWW
SET head off
SET feedback off
SET linesize 2000
-- EventService only Queued state
SELECT 'PAYMENT,0,' || COUNT(*)
FROM DAILY_SETTLEMENT_EVENTS_V1
WHERE EVENT_STATUS = 'QUEUED'
  AND SYS_EXTRACT_UTC(EVENT_STARTAT) <= SYSTIMESTAMP - INTERVAL '60' minute
UNION
SELECT 'SUBSCRIPTION,0,' || COUNT(*)
FROM EVENT_SUBSCRIPTION_STATUS
WHERE EVENT_STATUS = 'QUEUED'
  AND SYS_EXTRACT_UTC(EVENT_STARTAT) <= SYSTIMESTAMP - INTERVAL '60' minute
UNION
SELECT 'ASC,0,' || COUNT(*)
FROM ASC_RECORDS
WHERE EVENT_STATUS = 'QUEUED'
  AND SYS_EXTRACT_UTC(EVENT_STARTAT) <= SYSTIMESTAMP - INTERVAL '60' minute
UNION
SELECT 'EVENTS,0,' || COUNT(*)
FROM OBI_WEBHOOK_EVENTS
WHERE
    CASE EVENT_STATE WHEN 'QUEUED' THEN EVENT_STATE END = 'QUEUED'
  AND EVENT_TIMESTAMP <= SYSTIMESTAMP - INTERVAL '180' minute
UNION
SELECT 'MESSAGES,0,' || COUNT(*)
FROM OBI_WEBHOOK_MESSAGES
WHERE
    CASE MESSAGE_STATE WHEN 'QUEUED' THEN MESSAGE_STATE END = 'QUEUED'
  AND MESSAGE_START_AT <= SYSTIMESTAMP - INTERVAL '60' minute;
exit;
WWW
# testing
#echo "ABC ERRORS,10,last 1 hour,102"	>>/tmp/esb-bps-error-count.out
#echo "XYZ ERROR,0,last 1 hour,3"	>>/tmp/esb-bps-error-count.out

cat /tmp/esb-bps-error-count.out | egrep -v "^$" | sort -u >/tmp/esb-bps-error-count.uniq.out
cat /tmp/esb-bps-error-count.es_msg_delivery_state.out | egrep -v "^$" 	>/tmp/esb-bps-error-count.es_msg_delivery_state.uniq.out
cat /tmp/esb-bps-error-count.es_msg_queues_state.out | egrep -v "^$"    >/tmp/esb-bps-error-count.es_msg_queues_state.uniq.out
cat /tmp/esb-bps-error-count.es_only_queued_state.out | egrep -v "^$"    >/tmp/esb-bps-error-count.es_only_queued_state.uniq.out

cat /tmp/esb-bps-error-count.out /tmp/esb-bps-error-count.es_msg_delivery_state.out /tmp/esb-bps-error-count.es_msg_queues_state.out /tmp/esb-bps-error-count.es_only_queued_state.out >/tmp/esb-bps.errors

if [ $( cat /tmp/esb-bps.errors | egrep "ORA" | wc -l ) -ge 1 ]; then
	echo "Error: ORACLE errors found..."
	echo "<html><body><h3><br><br>Pls check ORACLE errors found...<br></h3>" 			>/tmp/esb-bps-error-count.rpt.${cts}.html
	echo "<font color="red">$( cat /tmp/esb-bps.errors | egrep ORA )</font><br><br></body></html>" 	>>/tmp/esb-bps-error-count.rpt.${cts}.html
	alarm_flag=2
else

	echo "<html><body><table style=\"width:60%\">"								>/tmp/esb-bps-error-count.rpt.${cts}.html
	echo "<br><h3>ESB-BPS Errors</h3>" >>/tmp/esb-bps-error-count.rpt.${cts}.html
	echo "<tr bgcolor="lightgrey"><th>TITLE</th><th>Timespan</th><th>Threshold</th><th>ERRORS</th></tr>"	>>/tmp/esb-bps-error-count.rpt.${cts}.html
		
	echo "alarm_flag=$alarm_flag"
	while read line
	do
		err_name=$( echo ${line} | awk -F"," '{print $1}' )
		err_threshold=$( echo ${line} | awk -F"," '{print $2}' )
		err_timespan=$( echo ${line} | awk -F"," '{print $3}' )
		err_count=$( echo ${line} | awk -F"," '{print $4}' )

		if [ ${err_count} -gt ${err_threshold} ]; then
			alarm_flag=1
			echo "<tr style=color:red><td>${err_name}</td><td>${err_timespan}</td><td>${err_threshold}</td><td>${err_count}</td></tr>"	>>/tmp/esb-bps-error-count.rpt.${cts}.html
		else
			echo "<tr style=color:><td>${err_name}</td><td>${err_timespan}</td><td>${err_threshold}</td><td>${err_count}</td></tr>"		>>/tmp/esb-bps-error-count.rpt.${cts}.html
		fi
		
	done </tmp/esb-bps-error-count.uniq.out
	echo "<br><h3>EventService Message Delivery State</h3>"	>>/tmp/esb-bps-error-count.rpt.${cts}.html
	echo "<table style=\"width:60%\">"										>>/tmp/esb-bps-error-count.rpt.${cts}.html
	echo "<tr bgcolor="lightgrey"><th>TITLE</th><th>Timespan</th><th>Threshold</th><th>FAILED_MESSAGES</th></tr>"       >>/tmp/esb-bps-error-count.rpt.${cts}.html
	while read line
                do
                        title=$( echo ${line} | awk -F"," '{print $1}' )
		threshold=$( echo ${line} | awk -F"," '{print $2}' )
                        timespan=$( echo ${line} | awk -F"," '{print $3}' )
                        failed_msgs=$( echo ${line} | awk -F"," '{print $4}' )

		if [ ${failed_msgs} -gt ${threshold} ]; then
                                alarm_flag=1
                        	echo "<tr style=color:red><td>${title}</td><td>${timespan}<td><td>${threshold}</td><td>${failed_msgs}</td></tr>"      >>/tmp/esb-bps-error-count.rpt.${cts}.html
		else
                        	echo "<tr style=color:><td>${title}</td><td>${timespan}<td><td>${threshold}</td><td>${failed_msgs}</td></tr>"      >>/tmp/esb-bps-error-count.rpt.${cts}.html
		fi

                done </tmp/esb-bps-error-count.es_msg_delivery_state.uniq.out

	echo "<br><h3>EventService Queues state</h3>" >>/tmp/esb-bps-error-count.rpt.${cts}.html
	echo "<table style=\"width:60%\">"										>>/tmp/esb-bps-error-count.rpt.${cts}.html
	echo "<tr bgcolor="lightgrey"><th>QUEUE NAME</th><th>STATUS</th><th>Timespan</th><th>Threshold</th><th>NUMBER_OF_EVENTS</th></tr>"       >>/tmp/esb-bps-error-count.rpt.${cts}.html
	while read line
                do
                        queue_name=$( echo ${line} | awk -F"," '{print $1}' )
                        queue_status=$( echo ${line} | awk -F"," '{print $2}' )
		threshold=$( echo ${line} | awk -F"," '{print $3}' )
                        timespan=$( echo ${line} | awk -F"," '{print $4}' )
                        num_of_recs=$( echo ${line} | awk -F"," '{print $5}' )
   
												if [ ${num_of_recs} -gt ${threshold} ]; then
													if [[ ${queue_status} != "QUEUED" ]]; then 
                            alarm_flag=1
													fi
                        	echo "<tr style=color:red><td>${queue_name}</td><td>${queue_status}</td><td>${timespan}<td><td>${threshold}</td><td>${num_of_recs}</td></tr>"      >>/tmp/esb-bps-error-count.rpt.${cts}.html
												else
                       		echo "<tr style=color:><td>${queue_name}</td><td>${queue_status}</td><td>${timespan}<td><td>${threshold}</td><td>${num_of_recs}</td></tr>"      >>/tmp/esb-bps-error-count.rpt.${cts}.html
												fi

                done </tmp/esb-bps-error-count.es_msg_queues_state.uniq.out
        echo "<br><h3>EventService Queued longer than 60 minutes</h3>" >>/tmp/esb-bps-error-count.rpt.${cts}.html
        echo "<table style=\"width:60%\">"                                                                              >>/tmp/esb-bps-error-count.rpt.${cts}.html
        echo "<tr bgcolor="lightgrey"><th>QUEUE NAME</th><th>Threshold</th><th>Count</th></tr>"       >>/tmp/esb-bps-error-count.rpt.${cts}.html
        while read line
                do
                        queue_name=$( echo ${line} | awk -F"," '{print $1}' )
                        threshold=$( echo ${line} | awk -F"," '{print $2}' )
			count=$( echo ${line} | awk -F"," '{print $3}' )

                if [ ${count} -gt ${threshold} ]; then
                                alarm_flag=1
                                echo "<tr style=color:red><td>${queue_name}</td><td>${threshold}</td><td>${count}</td></tr>"      >>/tmp/esb-bps-error-count.rpt.${cts}.html
                else
                                echo "<tr style=color:><td>${queue_name}</td><td>${threshold}</td><td>${count}</td></tr>"      >>/tmp/esb-bps-error-count.rpt.${cts}.html
                fi

                done </tmp/esb-bps-error-count.es_only_queued_state.uniq.out
                echo "</table><br><br></html>" 
	echo "</table><br><br>"												>>/tmp/esb-bps-error-count.rpt.${cts}.html
fi

FROM_EMAIL=${fromEmail}
RPT_BODY=/tmp/esb-bps-error-count.rpt.${cts}.html
RPT_SUBJ="test"
TO_EMAIL=${toEmail}
if [ ${alarm_flag} -eq 1 ]; then
	RPT_SUBJ="ESB-BPS ERROR COUNT (exceeding threshold) : ${cts}"
	TO_EMAIL=${toEmail}
	# send email notification
	email_report_func
elif [ ${alarm_flag} -eq 2 ]; then
	RPT_SUBJ="Failed : ESB-BPS ERROR COUNT : ${cts}"
	TO_EMAIL=${toEmailDev}
	# send email notification
	email_report_func
else
	RPT_SUBJ="ESB-BPS ERROR COUNT (all good) : ${cts}"
	TO_EMAIL=${toEmailDev}
	# send email notification
	email_report_func
	echo "###########: ${RPT_SUBJ}"
fi

else
echo "Usage: <script_name> <dbuser> <dbpassword>"
fi

rm -f /tmp/esb-bps-error-count.rpt.${cts}.html		2>/dev/null

echo "###########: End"

