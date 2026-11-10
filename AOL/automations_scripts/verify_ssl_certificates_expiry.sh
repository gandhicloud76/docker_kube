#!/bin/sh

set +x

#variables
prjHome=$(pwd)
prjTmp="${prjHome}/tmp"
prjOut="${prjHome}/out"

expiryCutOffDays=25
cts=$(date -u)
cts_epc=$(date -u '+%s' )
PORT=443

rm -Rf ${prjTmp} ${prjOut} 2>/dev/null
mkdir -p ${prjTmp} ${prjOut}

function notify_opsgenie_and_exit() {
  if [ $( cat ${prjOut}/error.txt | egrep "ERROR:" | wc -l ) -ge 1 ]; then
      echo -e "*****\n*****\n*****"
      echo "***** Sending notification via Ops Genie alarm to obi_prod_alerts slack alarm"
      echo -e "*****\n*****\n*****"
      exit 1
  fi
}


function verify_expiry(){
  expDate_epc=$1
  cts_epc=$2
  if [[ ! -z ${expDate_epc} ]] && [[ ! -z ${cts_epc} ]]; then
    if [[ ${expDate_epc} -lt ${cts_epc} ]]; then
      expireDays=$( echo "(${cts_epc} - ${expDate_epc})/86400" | bc )
      status_msg="Expired (${expireDays} days ago)"
    else
      expireDays=$( echo "(${expDate_epc} - ${cts_epc})/86400" | bc )
      if [[ ${expireDays} -le ${expiryCutOffDays} ]]; then
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

echo "########## Read Endpoints and verify expiry" 
echo -e ""
cp -p config/endpoints.ssl_certificates_expiry.txt ${prjTmp}/endpoints.ssl_certificates_expiry.txt

for endpoint in $( cat ${prjTmp}/endpoints.ssl_certificates_expiry.txt | egrep -v "^#" ); do
  # Use OpenSSL to check the certificate expiration date
  expDate=$(echo "" | openssl s_client -servername "${endpoint}" -connect "${endpoint}:$PORT" 2>/dev/null | openssl x509 -noout -dates | awk -F'=' '/notAfter/ {print $2}')
  if [[ -z ${expDate} ]]; then
    echo "ERROR: No expiration date for ${endpoint}" | tee -a ${prjOut}/report.csv
  else
    expDate_fmt=$(date -d "${expDate}" '+%Y-%m-%d %H:%M:%S')
    expDate_epc=$(date -d "${expDate}" '+%s' )
    status=$( verify_expiry ${expDate_epc} ${cts_epc})

    echo "SSL Certificate for ${endpoint} will expire on: ${expDate_fmt} --- ${status}"
    echo "${endpoint},${expDate_fmt},${status}" >>${prjOut}/report.csv
  fi
done

echo -e ""
echo "########## Verify if we are checking for all endpoints" 
echo -e ""

num_endpoints_expected_to_scan=$( cat ${prjTmp}/endpoints.ssl_certificates_expiry.txt | egrep -v "^#" | wc -l )
num_endpoints_actually_scanned=$( cat ${prjOut}/report.csv | wc -l )

if [[ ${num_endpoints_expected_to_scan} -eq ${num_endpoints_actually_scanned} ]]; then
  echo "### Match: All expected endpoints were scanned (#${num_endpoints_expected_to_scan})"
else
  echo "### ERROR: No Match: All expected endpoints were not scanned (Expected# ${num_endpoints_expected_to_scan}, Scanned# ${num_endpoints_actually_scanned})" | tee -a ${prjOut}/error.txt
  notify_opsgenie_and_exit
fi


echo -e ""
echo "########## Create HTML report" 
echo -e ""
echo "<html>
<h3>SSL Certifcates Expiry Report  (${cts})</h3>
<body>
<table border="1">
<tr>
<th bgcolor="lightblue">ENDPOINT</th>
<th bgcolor="lightblue">Expiry Date</th>
<th bgcolor="lightblue">Status</th>
</tr>"  >${prjOut}/report.html

if [[ -s ${prjOut}/report.csv ]]; then
  cat ${prjOut}/report.csv | while read inputLine; do
    col01=$( echo ${inputLine} | awk -F',' '{print $1}' )
    col02=$( echo ${inputLine} | awk -F',' '{print $2}' )
    col03=$( echo ${inputLine} | awk -F',' '{print $3}' )
  
    if [[ $( echo ${col03} | egrep "Expired|ERROR" | wc -l ) -eq 1 ]]; then 
      column_col="red"
    elif [[ $( echo ${col03} | egrep "Expiring Soon" | wc -l ) -eq 1 ]]; then
      column_col="blue"
    else
      column_col=""
    fi

    echo "<tr><td><font color=${column_col}>${col01}</font></td><td><font color=${column_col}>${col02}</font></td><td><font color=${column_col}>${col03}</font></td></tr>"  >>${prjOut}/report.html
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
