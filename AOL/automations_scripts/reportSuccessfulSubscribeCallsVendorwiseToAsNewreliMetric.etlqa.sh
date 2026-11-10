#!/bin/sh
if [ $# -eq 0 ]; then
scriptName=$0
runDt=$( date '+%Y-%m-%d' )
alarm_flag1=0
alarm_flag2=0
hostName=$( hostname )
echo "###########: Start script ${scriptName} is running on host ${hostName}"
. ~/.profile
#cleanup tmp files from previous run
rm -f /tmp/successful-subscribe-calls* 2>/dev/null

#function for checking environmental variables for custom metrics to newrelic Env
function check_variable_in_env() {
    x=$1
    if [ $( env | egrep "^${x}=" | wc -l ) -ne 1 ]; then
        echo "${x}: Variable not set in the Environment"
        exit 1
    fi
}

check_variable_in_env nrkey
check_variable_in_env BPS_DBPASSWD1
check_variable_in_env BPS_DBUSER1
check_variable_in_env BPS_DBSVR1

#function for posting custom metrics to newrelic Env - QA
function send_metrics() {
    vendorname=$1
    successcount=$2
    epochtime=$3

    curl -v -k -H "Content-Type: application/json" -H "Api-Key: ${nrkey}" -X POST https://metric-api.newrelic.com/metric/v1 \
    --data "[ { \"metrics\": [ { \"name\": \"subscriptions\", \"type\": \"count\", \"value\": $successcount, \"timestamp\": $epochtime, \"interval.ms\": 10000, \"attributes\": { \"vendorname\": \"$vendorname\" } } ] } ]"
}

# the SQLs to get the successful subscribe calls for each vendor in past 1 day window
sqlplus -S ${BPS_DBUSER1}/"${BPS_DBPASSWD1}"@"${BPS_DBSVR1}" >/tmp/successful-subscribe-calls.out 2>&1 <<XXX
SET head off
SET feedback off
SET linesize 2000
SET PAGESIZE 0

SET colsep ,
select REPLACE(NVL(SUBSTR(tvl.end_point,INSTR(tvl.end_point, '/',8)+1,(INSTR(tvl.end_point, '/', 9)-INSTR(tvl.end_point, '/',8)-1)),SUBSTR(tvl.end_point,INSTR(tvl.end_point, '//',9)+8,(LENGTH(tvl.end_point))-1)),'/','') as Domain_name,Count(*) as Success
from trans_vendor_log tvl 
where tvl.ACTION = 'SUBSCRIBE' and to_char(cast(tvl.created_dt as date),'DD-MM-YYYY') = to_char(cast(sysdate -1 as date),'DD-MM-YYYY')
and tvl.HTTP_STATUS between 200 and 299
group by NVL(SUBSTR(tvl.end_point,INSTR(tvl.end_point, '/',8)+1,(INSTR(tvl.end_point, '/', 9)-INSTR(tvl.end_point, '/',8)-1)),SUBSTR(tvl.end_point,INSTR(tvl.end_point, '//',9)+8,(LENGTH(tvl.end_point))-1))
order by Success desc,Domain_name;
exit;
XXX
cat /tmp/successful-subscribe-calls.out | sed "s/ //g" | sed "s/\t//g"| sed "s/\///g" | egrep -v "^$" | sort -u >/tmp/successful-subscribe-calls.uniq.out1
cat /tmp/successful-subscribe-calls.uniq.out1 | sed "s/\///g" >/tmp/successful-subscribe-calls.uniq.out
#cp x /tmp/successful-subscribe-calls.uniq.out
if [ -s /tmp/successful-subscribe-calls.uniq.out ]; then
        if [ $( cat /tmp/successful-subscribe-calls.uniq.out | egrep "ORA" | wc -l ) -ge 1 ]; then
                echo "Error: ORACLE errors found..."
                exit 1
        else
                while read line
                do
                        vendorname=$( echo ${line} | awk -F"," '{print $1}' )
                        successcount=$( echo ${line} | awk -F"," '{print $2}' )
                        #epochtime=$( date -d "-1 day" '+%s' )
			#epochtime=$( date -d "yesterday 0" '+%s' )
			epochtime=$( date -d "yesterday 23:59:59" '+%s' )
                        echo "$vendorname == $successcount == $epochtime"
                        send_metrics $vendorname $successcount $epochtime
                done </tmp/successful-subscribe-calls.uniq.out
        fi
fi
echo "Usage: <script_name> <dbuser> <dbpassword>"
fi
rm -f successful-subscribe-calls.out            2>/dev/null
rm -f successful-subscribe-calls.uniq.out       2>/dev/null
echo "###########: End"
