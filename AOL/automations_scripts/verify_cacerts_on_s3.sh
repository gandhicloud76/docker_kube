#!/bin/sh

set +x


#variables
prjHome=$(pwd)
prjInp="${prjHome}/in"
prjTmp="${prjHome}/tmp"
prjOut="${prjHome}/out"
export AWS_DEFAULT_REGION="us-east-1"
cts=$( date -u )
cts_epc=$( date -u '+%s' )
ENV=$1

if [[ $# -ne 1 ]]; then
  echo "### ERROR: Expecting ENV (qa or prod) as an argument"
  exit 1
fi

rm -Rf ${prjInp} ${prjTmp} ${prjOut} 2>/dev/null
mkdir -p ${prjInp} ${prjTmp} ${prjOut}

getAwsAuth(){
aws sts get-caller-identity

ASSUME_ROLE_RESP=$(aws sts assume-role --role-arn ${AWS_ROLE} --role-session-name jenkins --duration-seconds 1500)

export AWS_ACCESS_KEY_ID=$(echo "${ASSUME_ROLE_RESP}" |jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "${ASSUME_ROLE_RESP}" |jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "${ASSUME_ROLE_RESP}" |jq -r '.Credentials.SessionToken')

echo "#Now My Identity changed to:"
aws sts get-caller-identity
}


# Assume Role to read s3 bucket and download files
getAwsAuth

function notify_opsgenie_and_exit() {
	if [ $( cat ${prjOut}/error.txt | egrep "ERROR:" | wc -l ) -ge 1 ]; then
		echo -e "*****\n*****\n*****"
    echo "***** Sending notification via Ops Genie alarm to obi_prod_alerts slack alarm"
    echo -e "*****\n*****\n*****"
		exit 1
	fi
}

if [[ ${ENV} == "qa" ]]; then
  cp -p automations/cacerts_on_s3.exclude_list.qa.txt ${prjTmp}/exlude.lst
  S3_BUCKET="s3://obiengca/"
elif [[ ${ENV} == "prod" ]]; then
  cp -p automations/cacerts_on_s3.exclude_list.prod.txt ${prjTmp}/exlude.lst
  S3_BUCKET="s3://obi-ca/"
fi

echo -e "\n"
echo "########## Excluding below certs present"
cat ${prjTmp}/exlude.lst
echo -e ""

echo -e ""
echo "########## Copy files from ${S3_BUCKET}"
aws s3 cp --recursive ${S3_BUCKET} ${prjInp}/
if [[ $? -ne 0 ]]; then
	echo "### ERROR: Copying files from ${S3_BUCKET}" | tee -a ${prjOut}/error.txt
  notify_opsgenie_and_exit
fi
echo -e "\n\n\n\n"


function verify_expiry(){
	endDt_epc=$1
  cts_epc=$2
	if [[ ! -z ${endDt_epc} ]] && [[ ! -z ${cts_epc} ]]; then
    if [[ ${endDt_epc} -lt ${cts_epc} ]]; then
      expireDays=$( echo "(${cts_epc} - ${endDt_epc})/86400" | bc )
     	status_msg="Expired (${expireDays} days ago)"
    else
     	expireDays=$( echo "(${endDt_epc} - ${cts_epc})/86400" | bc )
      if [[ ${expireDays} -le 60 ]]; then
       	status_msg="Expiring Soon (in ${expireDays} days)"
      else
     		status_msg="Valid (for ${expireDays} days)"
      fi
    fi
  else
  	status_msg=NA
  fi
  echo "${status_msg}"
        
  return
}

cd ${prjInp}
echo "########## Read ObiRoot* directories for root cacerts and get details" 
echo -e ""
find . -maxdepth 1 -type d -name "ObiRoot*" | while read dirName
do
  ls ${dirName}/*crt		
done >${prjTmp}/root_cacert.tmp

cat ${prjTmp}/root_cacert.tmp | egrep -v -f ${prjTmp}/exlude.lst >${prjTmp}/root_cacert.lst

cat ${prjTmp}/root_cacert.lst | while read certFile
do
	subject=$( openssl x509 -noout -subject -in ${certFile}		2>/dev/null | awk -F= '{print $NF}' | sed -e 's/^[ \t]*//' )
  serial=$( openssl x509 -noout -serial -in ${certFile}		2>/dev/null | awk -F= '{print $NF}' | sed -e 's/^[ \t]*//' )
	startDt_tmp=$( openssl x509 -noout -startdate -in ${certFile}	2>/dev/null | awk -F= '{print $NF}' | sed -e 's/^[ \t]*//' )
  startDt=$(date -d "${startDt_tmp}" '+%Y-%m-%d %H:%M' )
  endDt_tmp=$( openssl x509 -noout -enddate -in ${certFile}  	2>/dev/null | awk -F= '{print $NF}' | sed -e 's/^[ \t]*//' )
  endDt=$(date -d "${endDt_tmp}" '+%Y-%m-%d %H:%M' )
  endDt_epc=$( date -u -d "${endDt}" '+%s' )
  status=$( verify_expiry ${endDt_epc} ${cts_epc})
  issuer=$( openssl x509 -noout -issuer -in ${certFile}		2>/dev/null | awk -F= '{print $NF}' | sed -e 's/^[ \t]*//' )
  issuer_serial=$( openssl x509 -noout -text -in ${certFile}	2>/dev/null | egrep -A5 "Authority Key Identifier:" | egrep "serial:" | sed "s/serial://g" | sed "s/://g" | sed "s/ //g")
 		
  if [[ ${serial} == ${issuer_serial} ]]; then
    echo "${certFile},${subject},${serial},${startDt},${endDt},${status},${issuer},${issuer_serial},complete" 		>>${prjOut}/root_cacert.csv
  else
    echo "${certFile},${subject},${serial},${startDt},${endDt},${status},${issuer},${issuer_serial},incomplete" 	>>${prjOut}/root_cacert.csv
  fi
done

if [[ -s ${prjOut}/root_cacert.csv ]]; then
	echo "### File created : ${prjOut}/root_cacert.csv"
	#cat ${prjOut}/root_cacert.csv
fi

echo -e ""
echo "########## Read ObiRoot* directories for root intermediate cacerts and get details" 
echo -e ""
find . -maxdepth 1 -type d -name "ObiRoot*" | while read dirName
do
  cat ${dirName}/ca.db.index | awk '{print $3}' | while read certHash
  do
  	if [[ -s ${dirName}/ca.db.certs/${certHash}.pem ]]; then
   		echo "${dirName}/ca.db.certs/${certHash}.pem"
    fi
  done
done	>${prjTmp}/root_intermediate_cacert.tmp
    
cat ${prjTmp}/root_intermediate_cacert.tmp | egrep -v -f ${prjTmp}/exlude.lst >${prjTmp}/root_intermediate_cacert.lst

cat ${prjTmp}/root_intermediate_cacert.lst | while read certFile
do
  subject=$( openssl x509 -noout -subject -in ${certFile}		2>/dev/null | awk -F= '{print $NF}' | sed -e 's/^[ \t]*//' )
  serial=$( openssl x509 -noout -serial -in ${certFile}		2>/dev/null | awk -F= '{print $NF}' | sed -e 's/^[ \t]*//' )
	startDt_tmp=$( openssl x509 -noout -startdate -in ${certFile}	2>/dev/null | awk -F= '{print $NF}' | sed -e 's/^[ \t]*//' )
  startDt=$(date -d "${startDt_tmp}" '+%Y-%m-%d %H:%M' )
  endDt_tmp=$( openssl x509 -noout -enddate -in ${certFile}  	2>/dev/null | awk -F= '{print $NF}' | sed -e 's/^[ \t]*//' )
  endDt=$(date -d "${endDt_tmp}" '+%Y-%m-%d %H:%M' )
  endDt_epc=$( date -u -d "${endDt}" '+%s' )
  status=$( verify_expiry ${endDt_epc} ${cts_epc})
  issuer=$( openssl x509 -noout -issuer -in ${certFile}		2>/dev/null | awk -F= '{print $NF}' | sed -e 's/^[ \t]*//' )
  issuer_serial=$( openssl x509 -noout -text -in ${certFile}	2>/dev/null | egrep -A5 "Authority Key Identifier:" | egrep "serial:" | sed "s/serial://g" | sed "s/://g" | sed "s/ //g")
        
  if [[ ${serial} == ${issuer_serial} ]]; then
   	echo "${certFile},${subject},${serial},${startDt},${endDt},${status},${issuer},${issuer_serial},complete" 		>>${prjOut}/root_intermediate_cacert.csv
  else
    echo "${certFile},${subject},${serial},${startDt},${endDt},${status},${issuer},${issuer_serial},incomplete" 	>>${prjOut}/root_intermediate_cacert.csv
    if [[  $( cat ${prjOut}/root_cacert.csv | egrep ",complete$" | awk -F',' '{print $3}' | egrep ${issuer_serial} | wc -l ) -eq 1 ]]; then
      extra_info=$( cat ${prjOut}/root_cacert.csv | egrep ",complete$" | egrep ",${issuer_serial}," | awk -F',' '{print $4","$5","$6}' )
      echo "${certFile},${subject},${serial},${startDt},${endDt},${status},${issuer},${issuer_serial},${extra_info},complete" 	>>${prjOut}/root_intermediate_cacert.csv
    else
      extra_info="NA,NA,NA"
      echo "${certFile},${subject},${serial},${startDt},${endDt},${status},${issuer},${issuer_serial},${extra_info},complete" 	>>${prjOut}/root_intermediate_cacert.csv
    fi
  fi
done

if [[ -s ${prjOut}/root_intermediate_cacert.csv ]]; then
	echo "### File created : ${prjOut}/root_intermediate_cacert.csv"
	#cat ${prjOut}/root_intermediate_cacert.csv
fi

echo -e ""
echo "########## Read ObiSigning* directories for obisigning cacerts and get details" 
echo -e ""
find . -maxdepth 1 -type d -name "ObiSigning*" | while read dirName
do
  ls ${dirName}/*crt		>${prjTmp}/obisigning_cacert.tmp
  cat ${dirName}/ca.db.index | awk '{print $3}' | while read certHash
  do
  	if [[ -s ${dirName}/ca.db.certs/${certHash}.pem ]]; then
   	  echo "${dirName}/ca.db.certs/${certHash}.pem"
    fi
  done	>>${prjTmp}/obisigning_cacert.tmp
    
  cat ${prjTmp}/obisigning_cacert.tmp | egrep -v -f ${prjTmp}/exlude.lst >${prjTmp}/obisigning_cacert.lst
    
  cat ${prjTmp}/obisigning_cacert.lst | while read certFile
  do
    subject=$( openssl x509 -noout -subject -in ${certFile}		2>/dev/null | awk -F= '{print $NF}' | sed -e 's/^[ \t]*//' )
    serial=$( openssl x509 -noout -serial -in ${certFile}		2>/dev/null | awk -F= '{print $NF}' | sed -e 's/^[ \t]*//' )
	  startDt_tmp=$( openssl x509 -noout -startdate -in ${certFile}	2>/dev/null | awk -F= '{print $NF}' | sed -e 's/^[ \t]*//' )
    startDt=$(date -d "${startDt_tmp}" '+%Y-%m-%d %H:%M' )
  	endDt_tmp=$( openssl x509 -noout -enddate -in ${certFile}  	2>/dev/null | awk -F= '{print $NF}' | sed -e 's/^[ \t]*//' )
   	endDt=$(date -d "${endDt_tmp}" '+%Y-%m-%d %H:%M' )
   	endDt_epc=$( date -u -d "${endDt}" '+%s' )
    status=$( verify_expiry ${endDt_epc} ${cts_epc})
    issuer=$( openssl x509 -noout -issuer -in ${certFile}		2>/dev/null | awk -F= '{print $NF}' | sed -e 's/^[ \t]*//' )
    issuer_serial=$( openssl x509 -noout -text -in ${certFile}	2>/dev/null | egrep -A5 "Authority Key Identifier:" | egrep "serial:" | sed "s/serial://g" | sed "s/://g" | sed "s/ //g")
        
    if [[ ${serial} == ${issuer_serial} ]]; then
      echo "${certFile},${subject},${serial},${startDt},${endDt},${status},${issuer},${issuer_serial},complete" 		>>${prjOut}/obisigning_cacert.csv
    else
     	echo "${certFile},${subject},${serial},${startDt},${endDt},${status},${issuer},${issuer_serial},incomplete" 	>>${prjOut}/obisigning_cacert.csv
      if [[  $( cat ${prjOut}/root_cacert.csv | egrep ",complete$" | awk -F',' '{print $3}' | egrep ${issuer_serial} | wc -l ) -eq 1 ]]; then
 		    extra_info=$( cat ${prjOut}/root_cacert.csv | egrep ",complete$" | egrep ",${issuer_serial}," | awk -F',' '{print $4","$5","$6}' )
        echo "${certFile},${subject},${serial},${startDt},${endDt},${status},${issuer},${issuer_serial},${extra_info},complete" 	>>${prjOut}/obisigning_cacert.csv
      elif [[  $( cat ${prjOut}/root_intermediate_cacert.csv | egrep ",complete$" | awk -F',' '{print $3}' | egrep ${issuer_serial} | wc -l ) -eq 1 ]]; then
 				extra_info=$( cat ${prjOut}/root_intermediate_cacert.csv | egrep ",complete$" | egrep ",${issuer_serial}," | awk -F',' '{print $4","$5","$6","$7","$8","$9","$10","$11}' )
        echo "${certFile},${subject},${serial},${startDt},${endDt},${status},${issuer},${issuer_serial},${extra_info},complete" 	>>${prjOut}/obisigning_cacert.csv
      else
        extra_info="NA,NA,NA"
        echo "${certFile},${subject},${serial},${startDt},${endDt},${status},${issuer},${issuer_serial},${extra_info},complete" 	>>${prjOut}/obisigning_cacert.csv
      fi
    fi
  done
done

if [[ -s ${prjOut}/obisigning_cacert.csv ]]; then
	echo "### File created : ${prjOut}/obisigning_cacert.csv"
	#cat ${prjOut}/obisigning_cacert.csv
fi

echo -e ""
echo "########## Verify if we are checking for all cacerts present" 
echo -e ""
# Testing: egrep "ObiRootCA2|ObiSigningCA2022"
find . -maxdepth 1 -type d \( -name "ObiSigning*" -o -name "ObiRoot*" \) | while read dirName
do
  ls ${dirName}/*crt	>>${prjTmp}/cacert_files.lst
  cat ${dirName}/ca.db.index | awk '{print $3}' | while read certHash
  do
  	if [[ -s ${dirName}/ca.db.certs/${certHash}.pem ]]; then
   		echo "${dirName}/ca.db.certs/${certHash}.pem" >>${prjTmp}/cacert_files.lst
    fi
  done
done

num_files_expected_to_scan=$( cat ${prjTmp}/cacert_files.lst | egrep -v -f ${prjTmp}/exlude.lst | awk '{print $NF}' | wc -l )
num_files_actually_scanned=$( cat ${prjOut}/*_cacert.csv | egrep ",complete$" | awk -F',' '{print $1}' | wc -l )

if [[ ${num_files_expected_to_scan} -eq ${num_files_actually_scanned} ]]; then
	echo "### Match: All expected files were scanned (#${num_files_expected_to_scan})"
else
	echo "List of files expected to scan:"
	cat ${prjTmp}/cacert_files.lst | awk '{print $NF}'    
	echo "List of files actually scanned:"
	cat ${prjOut}/*_cacert.csv | egrep ",complete$" | awk -F',' '{print $1}'
  echo "### No Match: All expected files were not scanned (Expected# ${num_files_expected_to_scan}, Scanned# ${num_files_actually_scanned})" | tee -a ${prjOut}/error.txt
  notify_opsgenie_and_exit
fi

echo -e ""
echo "########## Print Details" 
echo -e ""
cat ${prjOut}/*_cacert.csv | egrep ",complete$" | sed "s/,complete$//g" | sort >${prjOut}/report.csv

cat ${prjOut}/report.csv | while read inputLine
do
	numFields=$( echo ${inputLine} | awk -F',' '{print NF}' ) 

  col01=$( echo ${inputLine} | awk -F',' '{print $1}' )
  col02=$( echo ${inputLine} | awk -F',' '{print $2}' )
  col03=$( echo ${inputLine} | awk -F',' '{print $3}' )
  col04=$( echo ${inputLine} | awk -F',' '{print $4}' )
  col05=$( echo ${inputLine} | awk -F',' '{print $5}' )
  col06=$( echo ${inputLine} | awk -F',' '{print $6}' )
  col07=$( echo ${inputLine} | awk -F',' '{print $7}' )
  col08=$( echo ${inputLine} | awk -F',' '{print $8}' )
  col09=$( echo ${inputLine} | awk -F',' '{print $9}' )
  col10=$( echo ${inputLine} | awk -F',' '{print $10}' )
  col11=$( echo ${inputLine} | awk -F',' '{print $11}' )
  col12=$( echo ${inputLine} | awk -F',' '{print $12}' )
  col13=$( echo ${inputLine} | awk -F',' '{print $13}' )
  col14=$( echo ${inputLine} | awk -F',' '{print $14}' )
  col15=$( echo ${inputLine} | awk -F',' '{print $15}' )
  col16=$( echo ${inputLine} | awk -F',' '{print $16}' )
 
	if [[ $( echo ${col06} ${col11} ${col16} | egrep "Expired" | wc -l ) -eq 1 ]]; then
   	isExpired="*** ALERT: CERT ALREADY EXPIRED ***"
  elif [[ $( echo ${col06} ${col11} ${col16} | egrep "Expiring Soon" | wc -l ) -eq 1 ]]; then
   	isExpired="*** WARNING: CERT EXPIRING SOON ***"
  else
   	isExpired=""
  fi
    
  echo "### ${col01} ${isExpired}"
  echo "    subject              : ${col02}"
  echo "    serial               : ${col03}"
  echo "        start_date       : ${col04}"
  echo "        end_date         : ${col05}"
  echo "        status           : ${col06}"
  echo "    issuer               : ${col07}"
  echo "    issuer serial        : ${col08}"
    
  if [[ ${numFields} -eq 11 ]] || [[ ${numFields} -eq 16 ]]; then
    echo "        start_date       : ${col09}"
    echo "        end_date         : ${col10}"
    echo "        status           : ${col11}"
  fi
    
  if [[ ${numFields} -eq 16 ]]; then
    echo "    issuer rootca        : ${col12}"
    echo "    issuer rootca serial : ${col13}"
    echo "        start_date       : ${col14}"
    echo "        end_date         : ${col15}"
    echo "        status           : ${col16}"
  fi
    
  echo -e "\n"
done

echo -e ""
echo "########## Create HTML report" 
echo -e ""
echo "<html>
<h3>CA Certs Expiry Report  (on ${S3_BUCKET} - ${cts}</h3>
<body>
<table border="1">
<tr>
<th bgcolor="lightblue">Cert File on ${S3_BUCKET}</th>
<th bgcolor="lightblue">Subject</th>
<th bgcolor="lightblue">Serial</th>
<th bgcolor="lightblue">Start Date</th>
<th bgcolor="lightblue">End Date</th>
<th bgcolor="lightblue">Status</th>
<th bgcolor="lightblue">Issuer</th>
<th bgcolor="lightblue">Issuer Serial</th>
<th bgcolor="lightblue">Start Date</th>
<th bgcolor="lightblue">End Date</th>
<th bgcolor="lightblue">Status</th>
<th bgcolor="lightblue">Issuer RootCA</th>
<th bgcolor="lightblue">Issuer RootCA Serial</th>
<th bgcolor="lightblue">Start Date</th>
<th bgcolor="lightblue">End Date</th>
<th bgcolor="lightblue">Status</th>
</tr>"  >${prjOut}/report.html

if [[ -s ${prjOut}/report.csv ]]; then
  cat ${prjOut}/report.csv | while read inputLine
  do
   	col01=$( echo ${inputLine} | awk -F',' '{print $1}' )
  	col02=$( echo ${inputLine} | awk -F',' '{print $2}' )
   	col03=$( echo ${inputLine} | awk -F',' '{print $3}' )
   	col04=$( echo ${inputLine} | awk -F',' '{print $4}' )
   	col05=$( echo ${inputLine} | awk -F',' '{print $5}' )
   	col06=$( echo ${inputLine} | awk -F',' '{print $6}' )
   	col07=$( echo ${inputLine} | awk -F',' '{print $7}' )
   	col08=$( echo ${inputLine} | awk -F',' '{print $8}' )
   	col09=$( echo ${inputLine} | awk -F',' '{print $9}' )
   	col10=$( echo ${inputLine} | awk -F',' '{print $10}' )
   	col11=$( echo ${inputLine} | awk -F',' '{print $11}' )
   	col12=$( echo ${inputLine} | awk -F',' '{print $12}' )
   	col13=$( echo ${inputLine} | awk -F',' '{print $13}' )
   	col14=$( echo ${inputLine} | awk -F',' '{print $14}' )
   	col15=$( echo ${inputLine} | awk -F',' '{print $15}' )
   	col16=$( echo ${inputLine} | awk -F',' '{print $16}' )
              
    if [[ $( echo ${col06} ${col11} ${col16} | egrep "Expired" | wc -l ) -eq 1 ]]; then 
     	column_col="red"
    elif [[ $( echo ${col06} ${col11} ${col16} | egrep "Expiring Soon" | wc -l ) -eq 1 ]]; then
     	column_col="blue"
    else
     	column_col=""
    fi

	  echo "
	    <tr>
				<td><font color=${column_col}>${col01}</font></td>
				<td><font color=${column_col}>${col02}</font></td>
				<td><font color=${column_col}>${col03}</font></td>
				<td><font color=${column_col}>${col04}</font></td>
				<td><font color=${column_col}>${col05}</font></td>
				<td><font color=${column_col}>${col06}</font></td>
				<td><font color=${column_col}>${col07}</font></td>
				<td><font color=${column_col}>${col08}</font></td>
				<td><font color=${column_col}>${col09}</font></td>
				<td><font color=${column_col}>${col10}</font></td>
				<td><font color=${column_col}>${col11}</font></td>
				<td><font color=${column_col}>${col12}</font></td>
				<td><font color=${column_col}>${col13}</font></td>
				<td><font color=${column_col}>${col14}</font></td>
				<td><font color=${column_col}>${col15}</font></td>
				<td><font color=${column_col}>${col16}</font></td>
	   </tr>
  "  >>${prjOut}/report.html
  done
else
  echo "<tr>Report NA - Pls check</tr>" >>${prjOut}/report.html
fi
echo "</table></body></html>" >>${prjOut}/report.html

if [[ $( cat ${prjOut}/report.csv | egrep "Expired|Expiring Soon" | wc -l ) -ge 1 ]]; then
	echo "### ERROR: Cert(s) have either expired or expire in next 30 days. Check the output and HTML Report to know the details." | tee -a ${prjOut}/error.txt
  notify_opsgenie_and_exit
fi

set -x
