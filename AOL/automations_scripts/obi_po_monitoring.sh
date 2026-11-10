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
run_dt=`date "+%Y-%m-%d"`
cts=`date "+%Y-%m-%d-%H%M"`
BPSPRD_PWD=$( aws ssm get-parameter --name "/etlqa/bpsprd/gsrinivasan" --with-decryption --region us-east-1 --query "Parameter.Value" --output text )

if [[ -z ${BPSPRD_PWD} ]]; then
        echo "ERROR: not resolving password"
        exit 1
fi

#sqlplus prbhaip/'Make654iqt#!'@BPS_PRD > /home/ec2-user/prbhaip/mferrorcount1.out  2>&1 <<XXX
sqlplus  -S gsrinivasan/${BPSPRD_PWD}@'(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-bpsprd1-new.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021))(ADDRESS=(PROTOCOL=TCP)(HOST=oracle-bpsprd1.us-east-1.subscriptions.obi-db.aws.prod.private.aws.oath.cloud)(PORT=3021)))(CONNECT_DATA=(SERVICE_NAME=BPS_PRD)))' > /home/ec2-user/prbhaip/mferrorcount1.out  2>&1 <<XXX
SET heading on;
set lines 256
set trimout on
set tab off
set pagesize 100
SET feedback off
SET linesize 2000;


column Rivals_Count format 9999
column date format a20
column Error format a120
column Error_Code format a20

select count(distinct target_guid) as Rivals_Count,trunc (created_dt) as "date",status_obi_text as Error,status_obi_code as Error_Code from obi_transaction_log where created_dt > sysdate -1 and source_guid='rivalscom' and api_name='purchaseOffer' and status !=200 and status_obi_code not in ('OBI-29027','OM-2217','PAYBWS-317') group by trunc (created_dt),status_obi_text,status_obi_code ;

column GPS_Count format 9999
column date format a20
column Error format  a120 
column Error_Code format a20


select count(distinct target_guid) as GPS_Count,trunc (created_dt) as "date",status_obi_text as Error,status_obi_code as Error_Code from obi_transaction_log where created_dt > sysdate -1 and source_guid='GPS' and api_name='purchaseOffer' and status !=200 and status_obi_code not in ('OBI-29027','OM-2217','PAYBWS-317','OM-2216','OBI-1171','PAYBWS-306','SYS-3015','OM-2221','PAYBWS-318') group by trunc (created_dt),status_obi_text,status_obi_code ;

column Yahoo_Count format 9999
column date format a20
column Error format  a120 
column Error_Code format a20


select count(distinct target_guid) as Yahoo_Count,trunc (created_dt) as "date",status_obi_text as Error,status_obi_code as Error_Code from obi_transaction_log where created_dt > sysdate -1 and source_guid='yhoo' and api_name='purchaseOffer' and status !=200 and status_obi_code not in ('OBI-29027','OM-2217','PAYBWS-317','OM-2216','OBI-1171','PAYBWS-306','OBI-1176','OM-2221','OBI-1173','PAY-315') group by trunc (created_dt),status_obi_text,status_obi_code ;
exit;
XXX
cat   /home/ec2-user/prbhaip/mferrorcount1.out  | mailx -r do-not-reply@yahoo.net -s " PO ERROR  : ${cts} " anil.dalli@yahooinc.com  Sangeeta.bhatia@yahooinc.com shilpa.vontikommu@yahooinc.com 
You have new mail in /var/spool/mail/ec2-user