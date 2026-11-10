#!/usr/bin/sh 

set +x

#__author__ = 'anildalli'


# variables
prjHome=$(pwd); export prjHome
prjTmp=${prjHome}/tmp; export prjTmp
prjOut=${prjHome}/output; export prjOut
currentDt=$( date '+%Y-%m-%d' )
jenkinsIPaddress=$( hostname -I | awk '{print $1}' )

rm -rf ${prjTmp} ${prjOut}  2>/dev/null
mkdir -p ${prjTmp}
mkdir -p ${prjOut}

expiryCutOffDays=25
cts=$(date -u)
cts_epc=$(date -u '+%s' )

echo "# project-home      : ${prjHome}"
echo "# role-session-name : ${jenkinsIPaddress}"
echo "# current-timestamp : $( date '+%Y-%m-%d %H:%M')" | tee ${prjTmp}/error.log

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

for awsRegion in ${AWS_REGION}; do
echo "# awsRegion         : ${awsRegion}"

for currentAWSRole in ${AWS_ROLE}; do
    currentAWSAccount=$( echo ${currentAWSRole} | awk -F":" '{print $5}' )
      
    # skip to run non frontends-dev and frontends-prod account for us-west-2, ap-southeast-1, eu-west-1
    if [[ $( echo ${currentAWSAccount} | egrep "674961505149|559354210775" | wc -l ) -eq 0 ]]; then
        if [[ $( echo ${awsRegion} | egrep "us-west-2|ap-southeast-1|eu-west-1" | wc -l ) -eq 1 ]] ; then
            break
        fi
    fi

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
                if [ ${certType} != "AMAZON_ISSUED" ]; then 
                    continue 
                fi
                  
                domainName=$( cat ${prjTmp}/acmCertDescription.json | jq -r '.domainName' )
                certificateArn=$( cat ${prjTmp}/acmCertDescription.json | jq -r '.certificateArn' )
        
                createDt=$( cat ${prjTmp}/acmCertDescription.json | jq -r '.createDt' )
                createDtFmt=$( echo "${createDt}" | awk -F'T' '{print $1}' )
                                
                expiryDt=$( cat ${prjTmp}/acmCertDescription.json | jq -r '.expiryDt' )
                expiryDtFmt=$( echo "${expiryDt}" | awk -F'T' '{print $1}' )
                              
                expDate_epc=$(date -d "${expiryDt}" '+%s' )
                status=$( verify_expiry ${expDate_epc} ${cts_epc})

                AddDomainNames=$( aws --region ${awsRegion} acm describe-certificate --certificate-arn "${acmARN}" --output text | egrep "SUBJECTALTERNATIVENAMES" | awk '{print $2}' )
                AddDomainNamesFmt=$( echo "${AddDomainNames}" | tr '\n' ':' | sed "s/:$//g" )

                echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
                echo "domainName       =${AddDomainNamesFmt}"
                echo "createDtFmt      =${createDtFmt}"
                echo "expiryDtFmt      =${expiryDtFmt}"
                echo "certificateArn   =${certificateArn}"
                echo "certType         =${certType}"
                echo "status           =${status}"

                echo "${currentAWSAccount},${currentAWSAccountAlias},${awsRegion},${AddDomainNamesFmt},${expiryDtFmt},${status}"  >>${prjTmp}/html.log
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
    <th bgcolor="lightblue">Status</th>
    </tr>"  >${prjOut}/Report.html

    cat ${prjTmp}/html.log | sort -u | sort -t, -k5 | while read x
    do
        col1=$( echo $x | awk -F"," '{print $1}' )
        col2=$( echo $x | awk -F"," '{print $2}' )
        col3=$( echo $x | awk -F"," '{print $3}' )
        col4=$( echo $x | awk -F"," '{print $4}' )
        col5=$( echo $x | awk -F"," '{print $5}' )
        col6=$( echo $x | awk -F"," '{print $6}' )
        col6_col=''
        if [[ $( echo ${col6} | egrep "Expiring|Expired" |  wc -l ) -eq 1 ]]; then
            col6_col="red"
        else
            col6_col=''
        fi
                      
        echo "<tr>
            <td>${col1}</td>
            <td>${col2}</td>
            <td>${col3}</td>        
            <td>${col4}</td>
            <td>${col5}</td>
            <td bgcolor=${col6_col}>${col6}</td>
            </tr>"  >>${prjOut}/Report.html
    done
    echo "</table></body></html>" >>${prjOut}/Report.html

    # trigger OpsGenie alert in post build actions
    if [ $( cat ${prjTmp}/html.log | egrep "Expired|Expiring" | wc -l ) -ge 1 ]; then
        echo "***** ERROR or WARNING *****: Send Ops Genie alarm to obi_prod_alerts slack alarm in post build actions."
        echo "***** ERROR or WARNING *****: Please check the log for Expiring or Expired certificates."
        exit 1
    else
        echo "INFO             : All good. Nothing to alarm."
    fi
set -x
