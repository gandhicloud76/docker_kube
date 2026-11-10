#!/usr/bin/sh 

set +x

#__author__ = 'anildalli'


# variables
prjHome=$(pwd); export prjHome
prjTmp=${prjHome}/tmp; export prjTmp
prjOut=${prjHome}/output; export prjOut
currentDt=$( date '+%Y-%m-%d' )
jenkinsIPaddress=$( hostname -I | awk '{print $1}' )
rm -rf ${prjTmp}	2>/dev/null
mkdir -p ${prjTmp}/ssl/ouroath
mkdir -p ${prjOut}

echo "# project-home      : ${prjHome}"
echo "# role-session-name : ${jenkinsIPaddress}"
echo "# current-timestamp : $( date '+%Y-%m-%d %H:%M')"	| tee ${prjTmp}/error.log


for awsRegion in ${AWS_REGION}; do

echo "# awsRegion         : ${awsRegion}"

for currentAWSRole in ${AWS_ROLE}; do

	currentAWSAccount=$( echo ${currentAWSRole} | awk -F":" '{print $5}' )

	unset AWS_ACCESS_KEY_ID
	unset AWS_SECRET_ACCESS_KEY
	unset AWS_SECURITY_TOKEN

  aws sts assume-role --region ${awsRegion} --role-arn ${currentAWSRole} --role-session-name ${jenkinsIPaddress} 2>awscre-${currentAWSAccount}.err | \
    grep -w 'AccessKeyId\|SecretAccessKey\|SessionToken' | \
    sed 's/\"//g;s/\,//;s/ //g' > awscre-${currentAWSAccount};\

  if [[ -s awscre-${currentAWSAccount}.err ]]; then
    if [[ $( cat awscre-${currentAWSAccount}.err | egrep "RegionDisabledException" | wc -l ) -eq 1 ]]; then
      echo "################################################################"
      echo "AWS Account: ${currentAWSAccount}"
      echo "################################################################"
      echo "Warning: RegionDisabledException, skip"
      cat awscre-${currentAWSAccount}.err
      continue
    fi
  fi

	export AWS_ACCESS_KEY_ID=$( grep AccessKeyId awscre-${currentAWSAccount} | awk -F':' '{print $2}' );\
	export AWS_SECRET_ACCESS_KEY=$( grep SecretAccessKey awscre-${currentAWSAccount} | awk -F':' '{print $2}' );\
	export AWS_SECURITY_TOKEN=$( grep SessionToken awscre-${currentAWSAccount} | awk -F':' '{print $2}' );\

	if [ ! -z ${AWS_ACCESS_KEY_ID} ]; then  

		#get account alias
		currentAWSAccountAlias=$( aws --region ${awsRegion} iam list-account-aliases --output text | awk '{print $2}' )

		echo "################################################################"
		echo "AWS Account: ${currentAWSAccount} - ${currentAWSAccountAlias}"
		echo "################################################################"

		# list certificates from certificate manager
		echo ${SECRETS_MANAGER_CONFIG} | while read smCfgLine
		for smCfgLine in ${SECRETS_MANAGER_CONFIG}; do

			awsAccount=$( echo ${smCfgLine} | awk -F'|' '{print $1}' )
			smIdList=$( echo ${smCfgLine} | awk -F'|' '{print $2}' )
			smIdListFmt=$( echo ${smIdList} | tr ',' ':')

			echo "# awsAccount: ${awsAccount}"
			if [ ${currentAWSAccount} -eq ${awsAccount} ]; then

				echo ${smIdList} | tr ',' '\n' | egrep "digicert" | while read smId
				do
					echo "# Secret Manager Id (for Digi Certificate info): ${smId}"

					aws --region ${awsRegion} secretsmanager get-secret-value --secret-id ${smId} | jq --raw-output '.SecretString' >${prjTmp}/smSecrets.json

					if [ $( cat ${prjTmp}/smSecrets.json | egrep "OBI_DIGI_CERT" | wc -l ) -eq 1 ]; then
						OBI_DIGI_CERT_VALUE_ENCRYPTED=$( aws --region ${awsRegion} secretsmanager get-secret-value --secret-id ${smId} | jq --raw-output '.SecretString'| jq -r 'to_entries[] | select(.key == "OBI_DIGI_CERT")' | jq -r .value )
						echo -n "${OBI_DIGI_CERT_VALUE_ENCRYPTED}" | base64 -d 	>${prjTmp}/cert.pem
					fi
				done

				if [ -s ${prjTmp}/cert.pem ]; then
					domainName=$( openssl x509 -noout -subject -in ${prjTmp}/cert.pem | awk -F= '{print $NF}' | sed -e 's/^[ \t]*//' )
					startDt=$( openssl x509 -noout -startdate -in ${prjTmp}/cert.pem | awk -F= '{print $NF}' | sed -e 's/^[ \t]*//' )
					startDtFmt=$( date -d "${startDt}" '+%Y-%m-%d' )
					expiryDt=$( openssl x509 -noout -enddate -in ${prjTmp}/cert.pem | awk -F= '{print $NF}' | sed -e 's/^[ \t]*//' )
					expiryDtFmt=$( date -d "${expiryDt}" '+%Y-%m-%d' )
					serialNum=$( openssl x509 -noout -serial -in ${prjTmp}/cert.pem | awk -F= '{print $NF}' )

					echo "${domainName}:${expiryDtFmt}"
				fi

				renewReadyDt=$( date -d"-28 days ${expiryDtFmt}" '+%Y-%m-%d' )
				renewReadyStatus=0
				if [ $( echo ${renewReadyDt} | sed "s/-//g" ) -le $( echo ${currentDt} | sed "s/-//g" ) ]; then
					renewReadyStatus=1
				fi

				# CKMS_TLS_CONFIG is coming from jenkins parameter
                # format is pipe separated for fields for all domains whose certificates are in ACM 
                # dns-name|athenz-domain|ckms-keygroup|ckms-private-key|ckms-certificate
                ckmsInfoFound=0
				domainNameFmt=$( echo "${domainName}" | sed "s/\*//g" )
				if [ $( echo "${CKMS_TLS_CONFIG}" | awk -F"|" '{print $1}' | egrep "^${domainNameFmt}" | wc -l ) -eq 1 ]; then
					ckmsInfoFound=1
				fi

				echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
				if [ ${renewReadyStatus} -eq 1 ]; then
					echo "domainName       =${domainName}"
					echo "startDtFmt       =${startDtFmt}"
					echo "expiryDtFmt      =${expiryDtFmt}"
					echo "serialNum        =${serialNum}"
					echo "currentDt        =${currentDt}"
					echo "renewReadyDt     =${renewReadyDt}"
					echo "renewReadyStatus =${renewReadyStatus}"
					echo "ckmsInfoFound    =${ckmsInfoFound}"
				else			
					echo "domainName       =${domainName}"
					echo "expiryDtFmt      =${expiryDtFmt}"
					echo "renewReadyStatus =${renewReadyStatus}"
					echo "ckmsInfoFound    =${ckmsInfoFound}"
				fi

				if [ ${ckmsInfoFound} -eq 1 ]; then
					keygroupValue=$( echo "${CKMS_TLS_CONFIG}" | egrep "^${domainName}" | awk -F"|" '{print $3}' ) 
					privkeykeyValue=$( echo "${CKMS_TLS_CONFIG}" | egrep "^${domainName}" | awk -F"|" '{print $4}' )
					certkeygroupValue=${keygroupValue}
					certkeyValue=$( echo "${CKMS_TLS_CONFIG}" | egrep "^${domainName}" | awk -F"|" '{print $5}' )
				
					echo "keygroupValue    =${keygroupValue}"
					echo "privkeykeyValue  =${privkeykeyValue}"
					echo "certkeygroupValue=${certkeygroupValue}"
					echo "certkeyValue     =${certkeyValue}"
				fi

				if [[ ${renewReadyStatus} -eq 1 ]] && [[ ${ckmsInfoFound} -eq 1 ]]; then

					echo "INFO             : Certificate expires on ${expiryDtFmt}. Need to Renew."
					echo "${domainName}"	>${prjTmp}/dnsnames.txt
					if [ ! -s ${prjTmp}/dnsnames.txt ]; then
						echo "***** ERROR *****: dnsnames.txt file is empty or doesn't exist" | tee -a ${prjTmp}/error.log
						continue
					fi

					#cleanup previous run .pem files
					rm -f ${prjTmp}/ssl/ouroath/*pem	2>/dev/null
					rm -f ${prjTmp}/current*pem			2>/dev/null

					echo "INFO             : Running cameo..."
					cmdRunCameo="cameo deploy  --cert ${jenkinsAthenzCert} --key ${jenkinsAthenzKey} --keygroup ${keygroupValue} --privkeykey ${privkeykeyValue} --certkeygroup ${certkeygroupValue} --certkey ${certkeyValue} --path ${prjTmp}/ssl/ouroath --dnsnames ${prjTmp}/dnsnames.txt"
                    echo ${cmdRunCameo}
                    #exec ${cmdRunCameo}	
                    sudo cameo deploy  --cert ${jenkinsAthenzCert} --key ${jenkinsAthenzKey} --keygroup ${keygroupValue} --privkeykey ${privkeykeyValue} --certkeygroup ${certkeygroupValue} --certkey ${certkeyValue} --path ${prjTmp}/ssl/ouroath --dnsnames ${prjTmp}/dnsnames.txt
					if [ $? -ne 0 ]; then
						echo "***** ERROR *****: Running cameo" | tee -a ${prjTmp}/error.log
						continue
                    else
                        sudo chmod 754 ${prjTmp}/ssl/ouroath/*pem
					fi

					echo "Compare Serial number of current and new certificate..."

					if [ -s ${prjTmp}/ssl/ouroath/tls.cert.pem ]; then
						serialNumNew=$( openssl x509 -noout -serial -in ${prjTmp}/ssl/ouroath/tls.cert.pem | awk -F"=" '{print $2}' )
					fi
					echo "serialNumNew     =${serialNumNew}"
				
					if [ ${serialNum} != ${serialNumNew} ]; then
						echo "INFO             : Need to import new certificate (Current and new certificate serial numbers are different)."

						#Creating actual cert and chain from cert file
						if [ -s ${prjTmp}/ssl/ouroath/tls.cert.pem ]; then
							startActualCert=$( egrep -n "BEGIN CERTIFICATE" ${prjTmp}/ssl/ouroath/tls.cert.pem | head -1 | awk -F":" '{print $1}' )
							endActualCert=$( egrep -n "END CERTIFICATE" ${prjTmp}/ssl/ouroath/tls.cert.pem | head -1 | awk -F":" '{print $1}' )
							startChain=$( echo "${endActualCert} + 1" | bc )
                            endChain=$( cat -n ${prjTmp}/ssl/ouroath/tls.cert.pem | tail -1 | awk '{print $1}' )

							cat ${prjTmp}/ssl/ouroath/tls.cert.pem | sed -n "${startActualCert},${endActualCert}p"	>${prjTmp}/new.cert.pem
							cat ${prjTmp}/ssl/ouroath/tls.cert.pem | sed -n "${startChain},${endChain}p"	>${prjTmp}/new.chain.pem
							cp -p ${prjTmp}/ssl/ouroath/tls.key.pem ${prjTmp}/new.key.pem

							OBI_DIGI_CERT_VALUE_ENCRYPTED_NEW=$( cat ${prjTmp}/new.cert.pem | base64 -w 0 )
							OBI_DIGI_KEY_VALUE_ENCRYPTED_NEW=$( cat ${prjTmp}/new.key.pem | base64 -w 0 )
							OBI_DIGI_CHAIN_VALUE_ENCRYPTED_NEW=$( cat -v ${prjTmp}/new.chain.pem | base64 -w 0 )

						fi

						echo "INFO             : List cert, chain, key files to be used to update secrets manager"
						ls -l ${prjTmp}/new*pem


						echo ${smIdList} | tr ',' '\n' | while read smId
						do

							if [ $( echo ${smId} | egrep "digicert" | wc -l ) -eq 1 ]; then
								echo "INFO             : Update Secrets Manager - ${smId}"

								echo -e "{\n  \"OBI_DIGI_CERT\": \"${OBI_DIGI_CERT_VALUE_ENCRYPTED_NEW}\",\n  \"OBI_DIGI_KEY\": \"${OBI_DIGI_KEY_VALUE_ENCRYPTED_NEW}\"\n}"	>${prjTmp}/new.smSecrets.digicert.json

								aws --region ${awsRegion} secretsmanager update-secret --secret-id ${smId} --secret-string file://${prjTmp}/new.smSecrets.digicert.json
                        		if [ $? -ne 0 ]; then
                        			echo "***** ERROR *****: Running Update Secrets Manager - ${smId}" | tee -a ${prjTmp}/error.log
                           			continue
                        		fi
							elif [ $( echo ${smId} | egrep "digichain" | wc -l ) -eq 1 ]; then
								echo "INFO             : Update Secrets Manager - ${smId}"

								echo -e "{\n  \"OBI_DIGI_CHAIN\": \"${OBI_DIGI_CHAIN_VALUE_ENCRYPTED_NEW}\"\n}"	>${prjTmp}/new.smSecrets.digichain.json

								aws --region ${awsRegion} secretsmanager update-secret --secret-id ${smId} --secret-string file://${prjTmp}/new.smSecrets.digichain.json
                        		if [ $? -ne 0 ]; then
                        			echo "***** ERROR *****: Running Update Secrets Manager - ${smId}" | tee -a ${prjTmp}/error.log
                           			continue
                        		fi
                        	fi
                		done
					else
						echo "INFO: New Certificate not available in CKMS yet (Current and new certificate serial numbers are same)."
					fi
				elif [[ ${renewReadyStatus} -eq 1 ]] && [[ ${ckmsInfoFound} -eq 0 ]]; then
	        		echo "***** ERROR *****: Certificate expires on ${expiryDtFmt}. CKMS info NOT Known." | tee -a ${prjTmp}/error.log
				elif [[ ${renewReadyStatus} -eq 0 ]] && [[ ${ckmsInfoFound} -eq 1 ]]; then
	        		echo "INFO             : Certificate Valid. CKMS info is Known."
				else
	        		echo "!!!! WARNING !!!!: Certificate Valid. CKMS info NOT Known." | tee -a ${prjTmp}/error.log
				fi
				echo "${currentAWSAccount},${currentAWSAccountAlias},${domainName},${expiryDtFmt},${renewReadyDt},${renewReadyStatus},${ckmsInfoFound},${smIdListFmt}"	>>${prjTmp}/html.log
			
			fi
		done
	else
		echo "ERROR: AssumeRole operation"
	fi
  
	rm -f awscre-${currentAWSAccount} 2>/dev/null
	sleep 2
done
# end of loop for AWS Roles
done
# end of loop for AWs Regions

echo "<html>
<h3>Secrets Manager Certificates Status- ${currentDt}</h3>
<body>
<table border="1">
<tr>
<th bgcolor="lightblue">AWS Account</th>
<th bgcolor="lightblue">AWS Account Name</th>
<th bgcolor="lightblue">Domain</th>
<th bgcolor="lightblue">Secrets</th>
<th bgcolor="lightblue">Expiry Date</th>
<th bgcolor="lightblue">Auto Renew Date</th>
<th bgcolor="lightblue">Certificate Status</th>
<th bgcolor="lightblue">CKMS Info</th>
</tr>"	>${prjOut}/Secrets-Manager-Certificate-Renew-Report.html

cat ${prjTmp}/html.log | sort -u | sort -t, -k4 | while read x
do
	col1=$( echo $x | awk -F"," '{print $1}' )
	col2=$( echo $x | awk -F"," '{print $2}' )
	col3=$( echo $x | awk -F"," '{print $3}' )
	col4=$( echo $x | awk -F"," '{print $4}' )
	col4_ckms=$( date -d"-30 days ${col4}" '+%Y%m%d' )
	if [ $( echo ${currentDt} | sed "s/-//g" ) -ge ${col4_ckms} ]; then
		col4_col="yellow"
	else
		col4_col=""
	fi
	col5=$( echo $x | awk -F"," '{print $5}' )
	col6=$( echo $x | awk -F"," '{print $6}' )
	if [ ${col6} -eq 0 ]; then col6_col=""; col6_msg="Valid"; else col6_col="red"; col6_msg="Needs Renew"; fi
	col7=$( echo $x | awk -F"," '{print $7}' )
	if [ ${col7} -eq 0 ]; then col7_col="red"; col7_msg="Not Known"; else col7_col=""; col7_msg="Known"; fi
	col8_secrets=$( echo $x | awk -F"," '{print $8}' )
	echo "<tr>
	<td>${col1}</td>
	<td>${col2}</td>
	<td>${col3}</td>
	<td>${col8_secrets}</td>
	<td bgcolor=${col4_col}>${col4}</td>
	<td>${col5}</td>
	<td bgcolor=${col6_col}>${col6_msg}</td>
	<td bgcolor=${col7_col}>${col7_msg}</td>
	</tr>"	>>${prjOut}/Secrets-Manager-Certificate-Renew-Report.html
done
echo "</table></body></html>"	>>${prjOut}/Secrets-Manager-Certificate-Renew-Report.html

# trigger OpsGenie alert in post build actions
if [ $( cat ${prjTmp}/error.log | egrep "ERROR|WARNING" | wc -l ) -ge 1 ]; then
	echo "***** ERROR *****: Send Ops Genie alarm to obi_prod_alerts slack alarm in post build actions"
	exit 1
else
	echo "INFO             : All good. Nothing to alarm."
fi

#cleanup temporary files on completion of current run
echo "INFO             : Purged temporary files or certificates on completion of current run."
rm -rf ${prjTmp}	2>/dev/null


set -x

