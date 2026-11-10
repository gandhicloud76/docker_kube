#!/usr/local/bin

export AWS_PROFILE=federate
SSM_PARAM=$1

echo ""
echo ""
echo "This utility helps review the value of the same paramter defined in different regions to ensure it is consistent and we did not misconfigure"
echo ""
echo ""
AWS_REGION="us-east-1"
ACCT_NUM=$( aws --region ${AWS_REGION} sts get-caller-identity | jq -r '.Account' )
ARN=$( aws --region ${AWS_REGION} sts get-caller-identity | jq -r '.Arn' )
ACCT_ALIAS=$( aws --region ${AWS_REGION} iam list-account-aliases | jq -r '.AccountAliases[]' )
echo "-----------------------------------------"
echo "List Parameters from"
echo "        Region      : ${AWS_REGION}"
echo "        Account Num : ${ACCT_NUM}"
echo "        Account Name: ${ACCT_ALIAS}"
echo "        IAM Role    : ${ARN}" 
echo "-----------------------------------------"
sleep 3
echo ""
echo ""
aws --profile ${AWS_PROFILE} --region ${AWS_REGION} ssm describe-parameters | jq -r '.Parameters[].Name'
echo ""
echo ""
echo ""
echo "Choose any SSM Parameter (from above) to review its value across regions"
read SSM_PARAM
echo ""
echo ""
echo ""
function get_param(){
for AWS_REGION in ${MY_REGION_SELECTION}; do
echo "############## Parameter: ${SSM_PARAM}"
echo "############## Region   : ${AWS_REGION}"
for PARAM in $SSM_PARAM; do
  aws --profile ${AWS_PROFILE} --region ${AWS_REGION} ssm get-parameters --with-decryption --names ${PARAM} --query "Parameters[*].{Name:Name,Value:Value}" | jq -r '.[].Value'
done
done
}
echo ""
echo ""
echo ""
echo "Choose the Region(s):"
#PS3="Choose the Region(s):"
REGIONS_CHOICE=("us-east-1" "us-east-2" "us-west-2" "ap-southeast-1" "eu-west-1" "quit")
select MY_REGION_SELECTION in "${REGIONS_CHOICE[@]}"; do
    case ${MY_REGION_SELECTION} in
        "us-east-1")
            echo "You have selected Region - ${MY_REGION_SELECTION}"
            get_param
            ;;
        "us-east-2")
            echo "You have selected Region - ${MY_REGION_SELECTION}"
            get_param
            ;;
        "us-west-2")
            echo "You have selected Region - ${MY_REGION_SELECTION}"
            get_param
            ;;
        "ap-southeast-1")
            echo "You have selected Region - ${MY_REGION_SELECTION}"
            get_param
            ;;
        "eu-west-1")
            echo "You have selected Region - ${MY_REGION_SELECTION}"
            get_param
            ;;
        "quit")
            echo "Im exiting..."
            exit
            ;;
        *) 
            echo "Invalid option. Please select one of them - us-east-1, us-east-2, us-west-2, ap-southeast-1, eu-west-1"
            ;;
    esac
done
echo ""
echo ""

