set +x
#
# Pull obi/obi_ccp_be image, delete from ECR and push it back 
#
echo ""
echo ""
echo ""
echo ""
echo "### STEP: Check obi/obi_ccp_be:latest image present in ECR (prior refresh)"
if [[ $( aws --region us-east-1 ecr describe-images  --repository-name obi/obi_ccp_be --output json | jq -r '.imageDetails[].imageTags[]' ) == "latest" ]]; then
    echo "### INFO: Image present in psedev ECR"
    echo "### Image Tag"
    aws --region us-east-1 ecr describe-images  --repository-name obi/obi_ccp_be --output json | jq -r '.imageDetails[].imageTags[]'
	echo "### Image Pushed at"
    aws --region us-east-1 ecr describe-images  --repository-name obi/obi_ccp_be --output json | jq -r '.imageDetails[].imagePushedAt' | awk -F'+' '{print $1}' | sed "s/T/ /g"
else
    echo "### ERROR: Image NOT present in psedev ECR"
    echo "###"
    exit 1
fi

echo ""
echo ""
echo ""
echo ""
echo "### STEP: Pull image obi/obi_ccp_be:latest from ECR"
docker pull 665975628511.dkr.ecr.us-east-1.amazonaws.com/obi/obi_ccp_be:latest
if [[ $? -eq 0 ]]; then
	echo "### INFO: Image successfully pulled from ECR to local (jenkins server)"
	echo "###"
else
	echo "### ERROR: Image NOT pulled from ECR to local (jenkins server)"
	echo "###"
    exit 1
fi

echo ""
echo ""
echo ""
echo ""
echo "### STEP: Check pulled image obi/obi_ccp_be:latest present in local (jenkins server)"
if [[ $( docker images 665975628511.dkr.ecr.us-east-1.amazonaws.com/obi/obi_ccp_be:latest | egrep -v REPOSITORY | awk '{print $2}' | wc -l ) -eq 1 ]]; then
    echo "### INFO: Image present in local (jenkins server)"
    echo "###"
    docker images 665975628511.dkr.ecr.us-east-1.amazonaws.com/obi/obi_ccp_be:latest | egrep -v REPOSITORY | awk '{print $2}' 
else
	echo "### ERROR: Image NOT present in local (jenkins server)"
    echo "###"
    exit 1
fi

echo ""
echo ""
echo ""
echo ""
echo "### STEP: Delete image from ECR"
aws --region us-east-1 ecr batch-delete-image --repository-name obi/obi_ccp_be --image-ids imageTag=latest
if [[ $? -eq 0 ]]; then
	echo "### INFO: Image successfully deleted from ECR"
	echo "###"
else
	echo "### ERROR: Image NOT deleted from ECR"
	echo "###"
    exit 1
fi
echo ""
echo ""
echo ""
echo ""
echo "### STEP: Push image obi/obi_ccp_be:latest to ECR"
docker push 665975628511.dkr.ecr.us-east-1.amazonaws.com/obi/obi_ccp_be:latest
if [[ $? -eq 0 ]]; then
	echo "### INFO: Image successfully pushed to ECR"
	echo "###"
else
	echo "### ERROR: Image NOT pushed to ECR"
	echo "###"
    exit 1
fi

echo ""
echo ""
echo ""
echo ""
echo "### STEP: Check obi/obi_ccp_be:latest image present in ECR (post refresh)"
if [[ $( aws --region us-east-1 ecr describe-images  --repository-name obi/obi_ccp_be --output json | jq -r '.imageDetails[].imageTags[]' ) == "latest" ]]; then
    echo "### INFO: Image present in psedev ECR"
    echo "### Image Tag"
    aws --region us-east-1 ecr describe-images  --repository-name obi/obi_ccp_be --output json | jq -r '.imageDetails[].imageTags[]'
	echo "### Image Pushed at"
    aws --region us-east-1 ecr describe-images  --repository-name obi/obi_ccp_be --output json | jq -r '.imageDetails[].imagePushedAt' | awk -F'+' '{print $1}' | sed "s/T/ /g"
else
    echo "### ERROR: Image NOT present in psedev ECR"
    echo "###"
    exit 1
fi

set -x
