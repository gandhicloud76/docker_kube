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
		aws --region ${awsRegion} acm list-certificates --include keyTypes=RSA_2048,RSA_4096,EC_prime256v1 --query 'CertificateSummaryList[*].CertificateArn' --output json | egrep "arn" | sed "s/\"//g" | sed "s/ //g" | sed "s/,//g" >${prjTmp}/acmList.txt


		if [ -s ${prjTmp}/acmList.txt ]; then
			cat ${prjTmp}/acmList.txt | while read acmARN
			do
				aws --region ${awsRegion} acm describe-certificate --certificate-arn "${acmARN}" --query 'Certificate.{domainName:DomainName,certificateArn:CertificateArn,serialNum:Serial,createDt:CreatedAt,expiryDt:NotAfter,certType:Type}' --output json >${prjTmp}/acmCertDescription.json

				certType=$( cat ${prjTmp}/acmCertDescription.json | jq -r '.certType' )
				if [ ${certType} == "AMAZON_ISSUED" ]; then 
					continue 
				fi
                
				domainName=$( cat ${prjTmp}/acmCertDescription.json | jq -r '.domainName' )
				certificateArn=$( cat ${prjTmp}/acmCertDescription.json | jq -r '.certificateArn' )
				serialNum=$( cat ${prjTmp}/acmCertDescription.json | jq -r '.serialNum' | sed "s/://g" | tr 'a-z' 'A-Z')
				
				createDt=$( cat ${prjTmp}/acmCertDescription.json | jq -r '.createDt' )
				#createDtFmt=$( date -d@"${createDt}" '+%Y-%m-%d' )
				createDtFmt=$( echo "${createDt}" | awk -F'T' '{print $1}' )
				
				expiryDt=$( cat ${prjTmp}/acmCertDescription.json | jq -r '.expiryDt' )
				#expiryDtFmt=$( date -d@"${expiryDt}" '+%Y-%m-%d' )
				expiryDtFmt=$( echo "${expiryDt}" | awk -F'T' '{print $1}' )

				renewReadyDt=$( date -d"-28 days ${expiryDtFmt}" '+%Y-%m-%d' )
				renewReadyStatus=0
				if [ $( echo ${renewReadyDt} | sed "s/-//g" ) -le $( echo ${currentDt} | sed "s/-//g" ) ]; then
					renewReadyStatus=1
				fi

				AddDomainNames=$( aws --region ${awsRegion} acm describe-certificate --certificate-arn "${acmARN}" --output text | egrep "SUBJECTALTERNATIVENAMES" | awk '{print $2}' )
				AddDomainNamesFmt=$( echo "${AddDomainNames}" | tr '\n' ':' | sed "s/:$//g" )

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
					echo "domainName       =${AddDomainNamesFmt}"
					echo "createDtFmt      =${createDtFmt}"
					echo "expiryDtFmt      =${expiryDtFmt}"
					echo "serialNum        =${serialNum}"
					echo "certificateArn   =${certificateArn}"
					echo "certType         =${certType}"
					echo "currentDt        =${currentDt}"
					echo "renewReadyDt     =${renewReadyDt}"
					echo "renewReadyStatus =${renewReadyStatus}"
					echo "ckmsInfoFound    =${ckmsInfoFound}"
				else			
					echo "domainName       =${AddDomainNamesFmt}"
					echo "expiryDtFmt      =${expiryDtFmt}"
					echo "renewReadyStatus =${renewReadyStatus}"
					echo "ckmsInfoFound    =${ckmsInfoFound}"
				fi

				if [ ${ckmsInfoFound} -eq 1 ]; then
					keygroupValue=$( echo "${CKMS_TLS_CONFIG}" | egrep "^${domainName}" | awk -F"|" '{print $3}' ) 
					privkeykeyValue=$( echo "${CKMS_TLS_CONFIG}" | egrep "^${domainName}" | awk -F"|" '{print $4}' )
					certkeygroupValue=${keygroupValue}
					certkeyValue=$( echo "${CKMS_TLS_CONFIG}" | egrep "^${domainName}" | awk -F"|" '{print $5}' )
				
					#echo "jenkinsAthenzCert=${jenkinsAthenzCert}"
					#echo "jenkinsAthenzKey =${jenkinsAthenzKey}"
					echo "keygroupValue    =${keygroupValue}"
					echo "privkeykeyValue  =${privkeykeyValue}"
					echo "certkeygroupValue=${certkeygroupValue}"
					echo "certkeyValue     =${certkeyValue}"
				fi

				if [[ ${renewReadyStatus} -eq 1 ]] && [[ ${ckmsInfoFound} -eq 1 ]]; then

					echo "INFO             : Certificate expires on ${expiryDtFmt}. Need to Renew."
					echo "${AddDomainNames}"	>${prjTmp}/dnsnames.txt
					if [ ! -s ${prjTmp}/dnsnames.txt ]; then
						echo "***** ERROR *****: dnsnames.txt file is empty or doesn't exist" | tee -a ${prjTmp}/error.log
						continue
					fi
                    
                    #check to Exclude DNS from Renew
                    if [ $( echo "${EXCLUDE_DNS_FROM_RENEW}" | egrep -f ${prjTmp}/dnsnames.txt | wc -l ) -eq 1 ]; then
                        echo "WARNING          : Exclude DNS from Renew" | tee -a ${prjTmp}/error.log
                        echo "INSTRUCTIONS     : SCS reads SSL Cert/Chain from ACM; and PrivateKey from Parameter store while booting up."         | tee -a ${prjTmp}/error.log
                        echo "                   So when the certificates are refreshed in ACM, SCS needs to be re-deployed."                      | tee -a ${prjTmp}/error.log
                        echo ""                                                                                                                    | tee -a ${prjTmp}/error.log
                        echo "                   If you are seeing this message means, SCS Certs for (${AddDomainNamesFmt}) is ready for renewal." | tee -a ${prjTmp}/error.log
                        echo "                   Please follow below steps"                                                                        | tee -a ${prjTmp}/error.log
                        echo "                   [1] To Auto-Renew Certs in ACM and store the PrivateKey in Parameter Store."                      | tee -a ${prjTmp}/error.log
                        echo "                       Build with parameters the Jenkins job [ACM-Renew-SSL-Certificates] by removing the domain ${AddDomainNamesFmt} from EXCLUDE_DNS_FROM_RENEW." | tee -a ${prjTmp}/error.log
                        echo "                   [2] Once Certs in ACM are successfully updated, please re-deploy the SCS (${AddDomainNamesFmt}) service by running pipeline." | tee -a ${prjTmp}/error.log
                        echo ""                                                                                                                    | tee -a ${prjTmp}/error.log
                        echo "${currentAWSAccount},${currentAWSAccountAlias},${awsRegion},${AddDomainNamesFmt} (EXCLUDE FROM AUTO RENEWAL),${expiryDtFmt},${renewReadyDt},${renewReadyStatus},${ckmsInfoFound}"	>>${prjTmp}/html.log
                        continue
                    fi

					#cleanup previous run .pem files
					rm -f ${prjTmp}/ssl/ouroath/*pem	2>/dev/null
					rm -f ${prjTmp}/current*pem			2>/dev/null

					echo "INFO             : Running cameo..."
					cmdRunCameo="cameo deploy  --cert ${jenkinsAthenzCert} --key ${jenkinsAthenzKey} --keygroup ${keygroupValue} --privkeykey ${privkeykeyValue} --certkeygroup ${certkeygroupValue} --certkey ${certkeyValue} --path ${prjTmp}/ssl/ouroath --dnsnames ${prjTmp}/dnsnames.txt"
                    echo ${cmdRunCameo}
                    #exec ${cmdRunCameo}	
                    cameo deploy  --cert ${jenkinsAthenzCert} --key ${jenkinsAthenzKey} --keygroup ${keygroupValue} --privkeykey ${privkeykeyValue} --certkeygroup ${certkeygroupValue} --certkey ${certkeyValue} --path ${prjTmp}/ssl/ouroath --dnsnames ${prjTmp}/dnsnames.txt
					if [ $? -ne 0 ]; then
						echo "***** ERROR *****: Running cameo" | tee -a ${prjTmp}/error.log
						continue
                    else
                        chmod 754 ${prjTmp}/ssl/ouroath/*pem
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

							cat ${prjTmp}/ssl/ouroath/tls.cert.pem | sed -n "${startActualCert},${endActualCert}p"	>${prjTmp}/current.cert.pem
							cat ${prjTmp}/ssl/ouroath/tls.cert.pem | sed -n "${startChain},${endChain}p"	>${prjTmp}/current.chain.pem
							cp -p ${prjTmp}/ssl/ouroath/tls.key.pem ${prjTmp}/current.key.pem

              cat ${prjTmp}/current.cert.pem | base64   >${prjTmp}/current.cert.b64.pem
              cat ${prjTmp}/current.chain.pem | base64  >${prjTmp}/current.chain.b64.pem
              cat ${prjTmp}/current.key.pem | base64    >${prjTmp}/current.key.b64.pem
						fi

						echo "INFO             : List cert, chain, key files to be used to re-import Certififcate."
						ls -l ${prjTmp}/current*pem

						echo "INFO             : Import certificate to Certificate Manager."
						cmdRunAWSCertificateImport="aws --region ${awsRegion} acm import-certificate --certificate-arn ${certificateArn} --certificate file://${prjTmp}/current.cert.b64.pem --private-key file://${prjTmp}/current.key.b64.pem --certificate-chain file://${prjTmp}/current.chain.b64.pem"
                        echo ${cmdRunAWSCertificateImport}
                        #exec ${cmdRunAWSCertificateImport}
                        aws --region ${awsRegion} acm import-certificate --certificate-arn ${certificateArn} --certificate file://${prjTmp}/current.cert.b64.pem --private-key file://${prjTmp}/current.key.b64.pem --certificate-chain file://${prjTmp}/current.chain.b64.pem
                        if [ $? -ne 0 ]; then
                        	echo "***** ERROR *****: Running Import Certificate" | tee -a ${prjTmp}/error.log
                            continue
                        fi

                        # Pick the right cmk kms key used to overwrite ssm parameter /<dev|prod|sandbox>/scs-fg/privatekey
                        # SSM_KMS_KEY_CONFIG is coming from jenkins parameter
                        # format is pipe separated for fields having cmk kms key for all domains and region
                        # dns-name|aws-region|cmk-kms-key-arn
                        if [[ $( echo "${SSM_KMS_KEY_CONFIG}" | awk -F"|" '{print $1}' | egrep "^${domainNameFmt}" | wc -l ) -eq 1 ]] || [[ $( echo "${SSM_KMS_KEY_CONFIG}" | awk -F"|" '{print $1}' | egrep "^${domainNameFmt}" | wc -l ) -eq 2 ]]; then
                            if [ $( echo "${SSM_KMS_KEY_CONFIG}" | egrep "${domainNameFmt}" | awk -F"|" '{print $2}' | egrep "^${awsRegion}" | wc -l ) -eq 1 ]; then
                                ssmCmkKmsArn=$( echo "${SSM_KMS_KEY_CONFIG}" | egrep "${domainNameFmt}" | egrep "${awsRegion}" | awk -F"|" '{print $3}' )
                                echo "INFO             : SSM kms key arn - ${ssmCmkKmsArn}"
                            fi
                        fi


                        #Update Private Key in Parameter store for SCS dev, sandbox, prod
                        if [ $( echo ${AddDomainNamesFmt} | egrep "scs.dev.obi.aol.com" | wc -l ) -eq 1 ]; then
                            encodedPKey=$( cat ${prjTmp}/current.key.pem | base64 )
                            aws --region ${awsRegion} ssm put-parameter --name "/dev/scs-fg/privatekey" --type "SecureString" --key-id "${ssmCmkKmsArn}" --value "${encodedPKey}" --overwrite
                            if [ $? -ne 0 ]; then
                                echo "***** ERROR *****: Failed updating Private Key in Parameter Store /dev/scs-fg/privatekey for scs.dev.obi.aol.com"
																exit 1
                            else
                                echo "INFO             : Updated Private Key in Parameter Store /dev/scs-fg/privatekey for scs.dev.obi.aol.com"
                            fi
                        elif [ $( echo ${AddDomainNamesFmt} | egrep "scs.sandbox.obi.aol.com" | wc -l ) -eq 1 ]; then
                            encodedPKey=$( cat ${prjTmp}/current.key.pem | base64 )
                            aws --region ${awsRegion} ssm put-parameter --name "/sandbox/scs-fg/privatekey" --type "SecureString" --key-id "${ssmCmkKmsArn}" --value "${encodedPKey}" --overwrite
                            if [ $? -ne 0 ]; then
                                echo "***** ERROR *****: Failed updating Private Key in Parameter Store /sandbox/scs-fg/privatekey for scs.sandbox.obi.aol.com"
																exit 1
                            else
                                echo "INFO             : Updated Private Key in Parameter Store /sandbox/scs-fg/privatekey for scs.sandbox.obi.aol.com"
                            fi
                        elif [ $( echo ${AddDomainNamesFmt} | egrep "scs.obi.aol.com" | wc -l ) -eq 1 ]; then
                            encodedPKey=$( cat ${prjTmp}/current.key.pem | base64 )
                            aws --region ${awsRegion} ssm put-parameter --name "/prod/scs-fg/privatekey" --type "SecureString" --key-id "${ssmCmkKmsArn}" --value "${encodedPKey}" --overwrite
                            if [ $? -ne 0 ]; then
                                echo "***** ERROR *****: Failed updating Private Key in Parameter Store /prod/scs-fg/privatekey for scs.obi.aol.com"
																exit 1
                            else
                                echo "INFO             : Updated Private Key in Parameter Store /prod/scs-fg/privatekey for scs.obi.aol.com"
                            fi
                        fi
                        
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
				echo "${currentAWSAccount},${currentAWSAccountAlias},${awsRegion},${AddDomainNamesFmt},${expiryDtFmt},${renewReadyDt},${renewReadyStatus},${ckmsInfoFound}"	>>${prjTmp}/html.log
			done
		else
			echo "INFO             : No Certificates present."
		fi
	else
		echo "ERROR: AssumeRole operation" | tee -a ${prjTmp}/error.log
	fi
  
	rm -f awscre-${currentAWSAccount} 2>/dev/null
	sleep 2

done
# end of loop for AWS Roles
done
# end of loop for AWs Regions


echo "<html>
<h3>ACM Certificates Status- ${currentDt}</h3>
<body>
<table border="1">
<tr>
<th bgcolor="lightblue">AWS Account</th>
<th bgcolor="lightblue">AWS Account Name</th>
<th bgcolor="lightblue">Region</th>
<th bgcolor="lightblue">Domain(s)</th>
<th bgcolor="lightblue">Expiry Date</th>
<th bgcolor="lightblue">ACM Auto Renew Date</th>
<th bgcolor="lightblue">Certificate Status</th>
<th bgcolor="lightblue">CKMS Info</th>
</tr>"	>${prjOut}/Certificate-Renew-Report.html

cat ${prjTmp}/html.log | sort -u | sort -t, -k5 | while read x
do
	col1=$( echo $x | awk -F"," '{print $1}' )
	col2=$( echo $x | awk -F"," '{print $2}' )
	col3=$( echo $x | awk -F"," '{print $3}' )
	col4=$( echo $x | awk -F"," '{print $4}' )
    col5=$( echo $x | awk -F"," '{print $5}' )
	col5_ckms=$( date -d"-30 days ${col5}" '+%Y%m%d' )
	if [ $( echo ${currentDt} | sed "s/-//g" ) -ge ${col5_ckms} ]; then
		col5_col="yellow"
	else
		col5_col=""
	fi
	col6=$( echo $x | awk -F"," '{print $6}' )
	col7=$( echo $x | awk -F"," '{print $7}' )
	if [ ${col7} -eq 0 ]; then col7_col=""; col7_msg="Valid"; else col7_col="red"; col7_msg="Needs Renew"; fi
	col8=$( echo $x | awk -F"," '{print $8}' )
	if [ ${col8} -eq 0 ]; then col8_col="red"; col8_msg="Not Known"; else col8_col=""; col8_msg="Known"; fi
	echo "<tr>
	<td>${col1}</td>
	<td>${col2}</td>
	<td>${col3}</td>
    <td>${col4}</td>
	<td bgcolor=${col5_col}>${col5}</td>
	<td>${col6}</td>
	<td bgcolor=${col7_col}>${col7_msg}</td>
	<td bgcolor=${col8_col}>${col8_msg}</td>
	</tr>"	>>${prjOut}/Certificate-Renew-Report.html
done
echo "</table></body></html>"	>>${prjOut}/Certificate-Renew-Report.html
# trigger OpsGenie alert in post build actions
if [ $( cat ${prjTmp}/error.log | egrep "ERROR|WARNING" | wc -l ) -ge 1 ]; then
	echo "***** ERROR or WARNING *****: Send Ops Genie alarm to obi_prod_alerts slack alarm in post build actions."
    echo "***** ERROR or WARNING *****: Please check the log for ERROR or WARNING pattern to know the reason for failure."
	exit 1
else
	echo "INFO             : All good. Nothing to alarm."
fi
#cleanup temporary files on completion of current run
echo "INFO             : Purged temporary files or certificates on completion of current run."
rm -rf ${prjTmp}	2>/dev/null


set -x

