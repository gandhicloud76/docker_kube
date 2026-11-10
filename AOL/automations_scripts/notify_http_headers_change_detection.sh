#!/usr/bin/sh

set +x

#
# Notify on Unauthorized Modification of HTTP Headers change is detected by comparing the security headers 
# that is being deployed by the GIT code base (which is deployed as Lambda@Edge function associated with the CloudFront behavior for origin-response events)
# to the actual client-facing HTTP response headers (e.g., browser or curl).
#
echo ""
echo ""
echo "### INFO: Start Time $( date '+%Y-%m-%d %H:%M:%S' ) UTC"
echo "### INFO: Check to detect changes with HTTP Headers on consumers browser changes."
echo ""
echo ""
rm -f http_header.*.out	function.zip lambda_code		2>/dev/null

# default settings  ALARM
ALARM_FLAG=false
ALARM_HTTP_HEADERS=""


if [[ ${ENV} == "QA" ]]; then
	CLOUDFRONT_DOMAIN_ID="E305IPQ8W6KOQP"
	CLIENT_DOMAIN_NAMES=("https://jsl.qat.obi.aol.com/obipmservice/obick.umd.js" "https://jsl.qat.obi.aol.com/obick.umd.js")
	ROLE_NAME="arn:aws:iam::742442504506:role/subscriptions.obi-core.aws.dev.automation-jenkins"
elif [[ ${ENV} == "PROD" ]]; then
	CLOUDFRONT_DOMAIN_ID="E1JJL9DGOMCINP"
	CLIENT_DOMAIN_NAMES=("https://jsl.obi.aol.com/obipmservice/obick.umd.js" "https://jsl.obi.aol.com/obick.umd.js" "https://jsl.prod.obi.aol.com/obipmservice/obick.umd.js" "https://jsl.prod.obi.aol.com/obick.umd.js")
	ROLE_NAME="arn:aws:iam::673664509050:role/subscriptions.obi-black.aws.prod.automation-jenkins"
else
	echo "### ERROR : ENV variable is not QA or PROD or not defined. Exit"
	exit 1
fi

echo "####################################################################################################"
echo "### Running for ${ENV} Environment"
echo "####################################################################################################"
echo "### INFO  : CLOUDFRONT_DOMAIN_ID : ${CLOUDFRONT_DOMAIN_ID}"
if [ ${#CLIENT_DOMAIN_NAMES[@]} -eq 0 ]; then
	echo "### ERROR : The domain list is empty."
	exit 1
else
	echo "### INFO  : CLIENT_DOMAIN_NAMES  : ${CLIENT_DOMAIN_NAMES[@]}"
fi

echo "####################################################################################################"
echo "### Read Lambda Code from Git code base"
echo "### from OBI/obi_ops/sd_acct/cdn_httpheadersedgefunction_lambda/lambda_function_code/index.js"
echo "####################################################################################################"
echo "### INFO  : Git Lambda Code"
ls -1 obi_ops/sd_acct/cdn_httpheadersedgefunction_lambda/lambda_function_code/index.js

echo ""
echo ""
echo "####################################################################################################"
echo "### Get HTTP Header value from Git Lambda Code"
echo "####################################################################################################"
echo "### INFO   : Get value for content-security-policy or content-security-policy-report-only"
csp_value_git=$( egrep -A1 "Using ${ENV} CSP. Host Header:" obi_ops/sd_acct/cdn_httpheadersedgefunction_lambda/lambda_function_code/index.js | egrep "cspValue =" | awk -F" = " '{print $NF}' | sed "s/^\"//g" | sed "s/\";//g" | sed "s/$/\n/g" )
csp_value_git_sha256sum=$( echo -n "${csp_value_git}" | sha256sum | awk '{print $1}' )
echo "### INFO   : Get value for strict-transport-security"
sts_value_git=$( egrep "strict-transport-security" obi_ops/sd_acct/cdn_httpheadersedgefunction_lambda/lambda_function_code/index.js | awk -F"value: " '{print $NF}' | awk -F"'" '{print $2}' )
sts_value_git_sha256sum=$( echo -n "${sts_value_git}" | sha256sum | awk '{print $1}' )

echo "### INFO   : ROLE_NAME            : ${ROLE_NAME}"
echo ""
echo ""

unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SECURITY_TOKEN

currentAWSAccount=$( echo ${ROLE_NAME} | awk -F":" '{print $5}' )
  
aws sts assume-role --region "us-east-1" --role-arn ${ROLE_NAME} --role-session-name pci_jenkins 2>awscre-${currentAWSAccount}.err | \
		grep -w 'AccessKeyId\|SecretAccessKey\|SessionToken' | \
		sed 's/\"//g;s/\,//;s/ //g' > awscre-${currentAWSAccount};\

export AWS_ACCESS_KEY_ID=$( grep AccessKeyId awscre-${currentAWSAccount} | awk -F':' '{print $2}' );\
export AWS_SECRET_ACCESS_KEY=$( grep SecretAccessKey awscre-${currentAWSAccount} | awk -F':' '{print $2}' );\
export AWS_SECURITY_TOKEN=$( grep SessionToken awscre-${currentAWSAccount} | awk -F':' '{print $2}' );\

if [ -z ${AWS_ACCESS_KEY_ID} ]; then
	echo "### ERROR : AWS_ACCESS_KEY_ID is null"
	exit 1
fi

echo "####################################################################################################"
echo "### Get Lambda@Edge function code associated with the CloudFront behavior for origin-response events"
echo "####################################################################################################"
currentAWSAccountAlias=$( aws --region "us-east-1" iam list-account-aliases --output text | awk '{print $2}' )
echo "### INFO  : AWS Account          : ${currentAWSAccount} - ${currentAWSAccountAlias}"
    
# Get Lambda@Edge function name
lambdaedge_function_associated_with_cloudfront=$( aws --region "us-east-1" cloudfront get-distribution-config --id "${CLOUDFRONT_DOMAIN_ID}" | jq -r '.DistributionConfig.DefaultCacheBehavior.LambdaFunctionAssociations.Items[]?.LambdaFunctionARN' | awk -F"function:" '{print $NF}' )
echo "### INFO  : Lambda@Edge          : ${lambdaedge_function_associated_with_cloudfront}"

# Get Lambda Code
rm -rf function.zip lambda_code 2>/dev/null
curl -sSL "$( aws --region "us-east-1" lambda get-function --function-name "${lambdaedge_function_associated_with_cloudfront}" | jq -r '.Code.Location' )" -o function.zip
if [[ $? -ne 0 ]]; then
	echo "### ERROR : Curl failed to download Lambda zip"
fi
unzip function.zip -d lambda_code >/dev/null
if [[ $? -ne 0 ]]; then
	echo "### ERROR : Unzip failed"
fi
echo "### INFO  : Lambda@Edge Code     : $( ls -1 lambda_code/index.js )"

#echo ""
#echo ""
#echo "####################################################################################################"
#echo "### Get HTTP Header value set by Lambda@Edge for origin request"
#echo "####################################################################################################"
#echo "### INFO   : Get value for content-security-policy or content-security-policy-report-only"
#csp_value_lambda=$( egrep -A1 "Using ${ENV} CSP. Host Header:" lambda_code/index.js | egrep "cspValue =" | awk -F" = " '{print $NF}' | sed "s/^\"//g" | sed "s/\";//g" | sed "s/$/\n/g" )
#csp_value_lambda_sha256sum=$( echo -n "${csp_value_lambda}" | sha256sum | awk '{print $1}' )
#echo "### INFO   : Get value for strict-transport-security"
#sts_value_lambda=$( egrep "strict-transport-security" lambda_code/index.js | awk -F"value: " '{print $NF}' | awk -F"'" '{print $2}' )
#sts_value_lambda_sha256sum=$( echo -n "${sts_value_lambda}" | sha256sum | awk '{print $1}' )

echo ""
echo ""
echo "####################################################################################################"
echo "### Compare Git Lambda and Lambda@Edge"
echo "####################################################################################################"
echo "### INFO   : Git Lambda"
ls -l obi_ops/sd_acct/cdn_httpheadersedgefunction_lambda/lambda_function_code/index.js
git_lambda_sha256sum=$( sha256sum obi_ops/sd_acct/cdn_httpheadersedgefunction_lambda/lambda_function_code/index.js | awk '{print $1}' )

echo "### INFO   : Lambda@Edge"
ls -l lambda_code/index.js
lambda_edge_sha256sum=$( sha256sum lambda_code/index.js | awk '{print $1}' )

if [[ ${git_lambda_sha256sum} == ${lambda_edge_sha256sum} ]]; then
	echo "### SUCCESS: Git Lambda and Lambda@Edge is SAME"
	echo "           : sha256hash is same       : ${git_lambda_sha256sum}"
else
	echo "### ERROR  : Git Lambda and Lambda@Edge is DIFFERENT"
	echo "           : sha256hash git           : ${git_lambda_sha256sum}"
	echo "           : sha256hash lambda@edge   : ${lambda_edge_sha256sum}"
	ALARM_FLAG=true
fi

echo ""
echo ""
echo "####################################################################################################"
echo "### Notify if Git Lambda and Lambda@Edge is DIFFERENT to slack channel"
echo "### (if Post-build actions - Send Alerts to OpsGenie is enabled)"
echo "####################################################################################################"
echo "### INFO  : ALARM=${ALARM_FLAG}"
if [[ ${ALARM_FLAG} == "true" ]]; then
	echo "### ERROR : Git Lambda and Lambda@Edge is DIFFERENT"
	echo "          : Sending notification"
	exit 1  

else
	echo "### INFO  : Git Lambda and Lambda@Edge is SAME. Do not send notification."
fi 

for domain in "${CLIENT_DOMAIN_NAMES[@]}"; do
	echo ""
	echo ""
	echo "####################################################################################################"
	echo "### INFO   : Checking Domain - ${domain} for HTTP Header - content-security-policy or content-security-policy-report-only"
	echo "####################################################################################################"
	echo "### INFO   : Get the value from client browser by running http request"
	csp_value_client_browser=$( curl -sSI "${domain}" | grep -i "content-security-policy" | sed -e "s/^content-security-policy-report-only: //I" -e "s/^content-security-policy: //I" | tr -d '\r' )
	csp_value_client_browser_sha256sum=$( echo -n "${csp_value_client_browser}" | sha256sum | awk '{print $1}' )

	echo "### INFO   : Compare value from Git code (expected) and value from client browser"
	if [[ ${csp_value_git_sha256sum} == ${csp_value_client_browser_sha256sum} ]]; then
		echo "### SUCCESS: HTTP Header          : No change detected"
    		echo "           : sha256hash is same   : ${csp_value_git_sha256sum}"
    		echo "           : value is same        : ${csp_value_git}"
	else
		echo "### ERROR  : HTTP Header                   : Change detected"
    		echo "           : sha256hash git            : ${csp_value_git_sha256sum}"
    		echo "           : sha256hash client browser : ${csp_value_client_browser_sha256sum}"
    		echo "           : value git                 : ${csp_value_git}"
    		echo "           : value client browser      : ${csp_value_client_browser}"
        	echo "           : comparison of byte-level (hexadecimal) representations of two strings"
        	diff <(echo -n "${csp_value_git}" | xxd) <(echo -n "${csp_value_client_browser}" | xxd)
    
    		ALARM_HTTP_HEADERS="${domain}:content-security-policy"
    		ALARM_FLAG=true
	fi
done

for domain in "${CLIENT_DOMAIN_NAMES[@]}"; do
	echo ""
	echo ""
    	echo "####################################################################################################"
	echo "### INFO   : Checking Domain - ${domain} for HTTP Header - strict-transport-security"
    	echo "####################################################################################################"
	echo "### INFO   : Get the value from client browser by running http request"
	sts_value_client_browser=$( curl -sSI "${domain}" | grep -i 'strict-transport-security' | sed "s/^strict-transport-security: //g" | tr -d '\r' )
	sts_value_client_browser_sha256sum=$( echo -n "${sts_value_client_browser}" | sha256sum | awk '{print $1}' )

	echo "### INFO   : Compare value form Git code (expected) and value from client browser"
	if [[ ${sts_value_git_sha256sum} == ${sts_value_client_browser_sha256sum} ]]; then
		echo "### SUCCESS: HTTP Header          : No change detected"
    		echo "           : sha256hash is same   : ${sts_value_git_sha256sum}"
    		echo "           : value is same        : ${sts_value_git}"
	else
		echo "### ERROR  : HTTP Header                   : Change detected"
    		echo "           : sha256hash git            : ${sts_value_git_sha256sum}"
    		echo "           : sha256hash client browser : ${sts_value_client_browser_sha256sum}"
    		echo "           : value git                 : ${sts_value_git}"
    		echo "           : value client browser      : ${sts_value_client_browser}"
        	echo "           : comparison of byte-level (hexadecimal) representations of two strings"
        	diff <(echo -n "${sts_value_git}" | xxd) <(echo -n "${sts_value_client_browser}" | xxd)
    
    		ALARM_HTTP_HEADERS+=" ${domain}:strict-transport-security"
    		ALARM_FLAG=true
	fi
done

echo ""
echo ""
echo "####################################################################################################"
echo "### Notify for HTTP Header change detected between Git code (expected) and Client Browser to slack channel"
echo "### (if Post-build actions - Send Alerts to OpsGenie is enabled)"
echo "####################################################################################################"
echo "### INFO  : ALARM=${ALARM_FLAG}"
if [[ ${ALARM_FLAG} == "true" ]]; then
	echo "### INFO  : Detected unauthorized modification of HTTP Headers. Send notification."
	if [[ ! -z ${ALARM_HTTP_HEADERS} ]]; then
		echo "### ERROR : Unauthorized modification of HTTP Headers detected"
		echo "### ERROR : ${ALARM_HTTP_HEADERS}"
		echo "          : Sending notification"
		exit 1  
	fi
 else
	echo "### INFO  : Not detected unauthorized modification of HTTP Headers. Do not send notification."
fi 

echo ""
echo ""
echo "### INFO: End Time $( date '+%Y-%m-%d %H:%M:%S' ) UTC"
echo ""
echo ""

set -x
