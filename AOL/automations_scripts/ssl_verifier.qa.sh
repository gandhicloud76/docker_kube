#!/bin/bash

echo "My Ip: `curl ipinfo.io`"


#aol.xbus.prod.services.aol.com:443,0,1_1
#mess.aol.com:443,3,1_2 (IP Blocked)
#jsl.prod.obi.aol.com:443,0,1_2
#partners.pse.aol.com:9443,5,1_2



endpoints() {
#Format: host:port,NumberOfClientCAs,minTlsVersion(1,1_1,1_2)
cat<<-EOF
ssl.qat.obi.aol.com:443,9,1_2
tls.prod.obi.aol.com:443,8,1_2
checkout.aol.com:443,0,1
partners.pse.aol.com:443,5,1_2
scare.obi.aol.com:443,0,1_1
aol.xbus.prod.services.aol.com:443,0,1_2
api.qat.obi.aol.com:443,0,1_2
partners-prod.pse.aws.oath.cloud:443,5,1_2
EOF
}

verifyCAs(){

printf "\n\n##### Verifying CA's for: ${1} #####\n"
openssl version
curl --version
host=$(echo ${1}|cut -d":" -f1)
#CA_COUNT=$(echo Q |openssl s_client -connect ${1} -servername ${host} 2>/dev/null |sed --quiet '/Acceptable client certificate CA names/,/---/p' |grep -e 'us-east-1/CN=Athenz AWS CA' -e 'us-west-2/CN=Athenz AWS CA' -e 'Athenz Bfv/CN=Yahoo Athenz CA' -e 'Athenz Gqv/CN=Yahoo Athenz CA' -e 'Athenz Tcv/CN=Yahoo Athenz CA' -e 'OBI Intermediate CA' -e 'OBI Root CA' |wc -l)
#update on 10/19 added new patterns
#update on 10/20 included old patterns too
#update on 3/6 to fix frequent failures for not getting CA list
#CA_COUNT=$(echo Q |openssl s_client -connect ${1} -servername ${host} 2>/dev/null |sed --quiet '/Acceptable client certificate CA names/,/---/p' |grep -e 'us-east-1/CN=Athenz AWS CA' -e 'us-west-2/CN=Athenz AWS CA' -e 'Athenz Bfv/CN=Yahoo Athenz CA' -e 'Athenz Gqv/CN=Yahoo Athenz CA' -e 'Athenz Tcv/CN=Yahoo Athenz CA' -e 'us-east-1, CN = Athenz AWS CA' -e 'us-west-2, CN = Athenz AWS CA' -e 'Athenz Bfv, CN = Yahoo Athenz CA' -e 'Athenz Gqv, CN = Yahoo Athenz CA' -e 'Athenz Tcv, CN = Yahoo Athenz CA' -e 'OBI Intermediate CA' -e 'OBI Root CA' |wc -l)
#CA_LIST=$(echo Q |openssl s_client -connect ${1} -servername ${host} 2>/dev/null |sed --quiet '/Acceptable client certificate CA names/,/---/p')

echo Q |openssl s_client -connect ${1} -servername ${host} 2>/dev/null |sed --quiet '/Acceptable client certificate CA names/,/---/p'	>/tmp/ca.lst
if [ ! -s /tmp/ca.lst ]; then
    if [ $( echo ${1} | egrep "ssl.qat.obi.aol.com|tls.prod.obi.aol.com|partners.pse.aol.com|partners-prod.pse.aws.oath.cloud" | wc -l ) -eq 1 ]; then
   .    echo Q |openssl s_client -connect ${1} -servername ${host} 2>/dev/null |sed --quiet '/Acceptable client certificate CA names/,/---/p'	>/tmp/ca.lst
    fi
fi
	
CA_COUNT=$(cat /tmp/ca.lst |grep -e 'us-east-1/CN=Athenz AWS CA' -e 'us-west-2/CN=Athenz AWS CA' -e 'Athenz Bfv/CN=Yahoo Athenz CA' -e 'Athenz Gqv/CN=Yahoo Athenz CA' -e 'Athenz Tcv/CN=Yahoo Athenz CA' -e 'us-east-1, CN = Athenz AWS CA' -e 'us-west-2, CN = Athenz AWS CA' -e 'Athenz Bfv, CN = Yahoo Athenz CA' -e 'Athenz Gqv, CN = Yahoo Athenz CA' -e 'Athenz Tcv, CN = Yahoo Athenz CA' -e 'OBI Intermediate CA' -e 'OBI Root CA' |wc -l)

echo "Current CA List for ${1}:"
cat /tmp/ca.lst

if [ "${CA_COUNT}" -eq ${2} ];then 
    echo "All CA's Present"
    rm -f /tmp/ca_mismatch_found.txt 2>/dev/null
else 
    echo "CA Mismatch got:  ${CA_COUNT} , Expected: ${2}"
    touch /tmp/ca_mismatch_found.txt
    #exit 1
fi

}


checkExpDate() {
printf "\n\n##### Verifying Expiration Date for: ${1} #####\n"
host=$(echo ${1}|cut -d":" -f1)
CURR_DATE=$(date "+%s")
EXP_DATE=$(date -d "$(echo Q |openssl s_client -connect ${1} -servername ${host} 2>/dev/null |openssl x509 -noout -enddate|cut -d"=" -f2)"  +"%s")


DIFF=$(expr ${EXP_DATE} - ${CURR_DATE})

if [ ${DIFF} -le 604800 ];then
    echo "Cert is expirting less than 1 week for ${1} end point"
    echo "Expiration Date: ${EXP_DATE}"
    echo Q |openssl s_client -connect ${1} -servername ${host} 2>/dev/null |openssl x509 -noout -text

    exit 1
else
    echo "Cert for ${1} Expring on: `date -d @${EXP_DATE}` "
fi

}


tlsOrder(){
cat<<-EOF
tls1
tls1_1
tls1_2
EOF
}


verifySSLProtocols() {

printf "\n\n#### TLS Protocols ${1} Supports ####\n"


host=$(echo ${1}|cut -d":" -f1)
tls1=$(echo q|openssl s_client -connect ${1} -servername ${host} -tls1  2>&1|grep 'Server certificate' |wc -l)
tls1_1=$(echo q|openssl s_client -connect ${1} -servername ${host} -tls1_1  2>&1|grep 'Server certificate' |wc -l)
tls1_2=$(echo q|openssl s_client -connect ${1} -servername ${host} -tls1_2  2>&1|grep 'Server certificate' |wc -l)



if [ ${tls1_2} -gt 0 ];then
    echo "${1} Supports tls v1.2"
fi

if [ ${tls1_1} -gt 0 ];then
    echo "${1} Supports tls v1.1"
fi

if [ ${tls1} -gt 0 ];then
    echo "${1} Supports tls v1"
fi


echo "Minimum TLS Version requirement is TLSv${2}"

#Find which TLS versions should fail.
versions=()

for version in `tlsOrder`;do
#echo " ###### Checking  ${version} #####" 
if [ tls${2} == ${version}  ];then
	#echo "###### Matching ${version} #####" 
    break
fi
versions+=" ${version}"
done


tlsCheck=success
for version in ${versions};do
if [ "${!version}" -gt 0 ];then
	 echo "Failure: ${1} supports ${version}"
     tlsCheck=failure
fi
done

if [ ${tlsCheck} == "failure" ];then
	echo "Failed TLS Protocol validation"
    exit 1
fi


}


verifyCipherStrength() {
host=${1}
port=${2}

protocol=$(nmap -sV --version-light --script ssl-enum-ciphers -p ${port} ${host}|grep 'least strength'|cut -d":" -f2|sed "s/ //g")
if [[ -z "${protocol}" ]]; then
	echo "Retry to find Strength of ciphers after sleeping for 10 mins"
    sleep 600
	protocol=$(nmap -sV --version-light --script ssl-enum-ciphers -p ${port} ${host}|grep 'least strength'|cut -d":" -f2|sed "s/ //g")
fi
echo "Strength of ciphers: #####${protocol}####"

if [[ "${protocol}" != "A" ]] && [[ "${protocol}" != "strong" ]];then
	echo "Found Weak ciphers"
    echo "scanning ${host} ${port}"
    nmap --script ssl-enum-ciphers ${host} -p ${port}
    exit 1
fi


}


for line in `endpoints`;do

  #Variables
  endPoint=`echo ${line}|cut -d"," -f1`
  host=`echo ${endPoint}|cut -d":" -f1`
  port=`echo ${endPoint}|cut -d":" -f2`
  count=`echo ${line}|cut -d"," -f2`
  tlsVersion=`echo ${line}|cut -d"," -f3`
  
  
  #Checks CAs
  max_retries=4
  retry_count=1
  while [[ $retry_count -lt $max_retries ]]; do
      verifyCAs ${endPoint} ${count}
      if [[ ! -f /tmp/ca_mismatch_found.txt ]]; then
          echo "VerifyCAs: Attempt ${retry_count} of $max_retries. Success."
          break
      else
          sleep_secs=$( echo "${retry_count} * 120" | bc )
	  echo "VerifyCAs: Attempt ${retry_count} of $max_retries. Retry again after sleep of ${sleep_secs}."
          retry_count=$( echo "${retry_count} + 1" | bc )
	  sleep ${sleep_secs}
      fi
  done

  if [ $retry_count -eq $max_retries ]; then
      echo "VerifyCAs: CAs Mismatch still present after $max_retries attempts."
      exit 1
  fi
  
  #Checks Expiry Date
  checkExpDate ${endPoint}
  
  #Checks SSL Protocols
  verifySSLProtocols ${endPoint} ${tlsVersion}
  
  #Checks Cipher Strength
  verifyCipherStrength ${host} ${port}

done

