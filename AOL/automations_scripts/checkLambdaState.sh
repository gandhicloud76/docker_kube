
tmpDir="/tmp"

mkdir -p ${tmpDir}

echo "##### Run awsfed to get all aws account numbers"
echo '0' | awsfed -n | grep Account | sed "s/ //g" | awk -F':' '{print $3","$4}' >${tmpDir}/awsfed.out
cp /tmp/awsfed.tmp /tmp/awsfed.out

cat ${tmpDir}/awsfed.out | awk -F',' '{print $1}' | awk -F'(' '{print $1}' | sort -u | while read acctNum
do
	acctName=$( cat ${tmpDir}/awsfed.out | egrep ${acctNum} | awk -F',' '{print $1}' | awk -F'(' '{print $2}' | awk -F')' '{print $1}' | sort -u )
	roleName=$( cat ${tmpDir}/awsfed.out | egrep ${acctNum} | awk -F',' '{print $2}' | head -1 )

	#echo ""
	#echo "${acctNum}......................"

	# login to each distinct aws account
	awsfed --profile=${acctName} --account=${acctNum} --role=${roleName} -n >/dev/null 2>&1
	export AWS_PROFILE=${acctName}

	# get list of aws regions
	aws ec2 describe-regions --region us-east-1 | jq -r '.Regions[].RegionName' >${tmpDir}/awsRegions.out

	# loop through each region
#	for awsRegion in `cat ${tmpDir}/awsRegions.out`
#	do
#    aws --region ${awsRegion} lambda list-functions | jq -r '.Functions[].FunctionName' | while read lambdaName
#    do
#		  lambdaState=$( aws --region ${awsRegion} lambda get-function --function-name ${lambdaName} | jq -r '.Configuration.State' )
#      echo "${acctNum},${acctName},${awsRegion},${lambdaName},${lambdaState}"
#    done
#	done

  for awsRegion in `cat ${tmpDir}/awsRegions.out`
  do
    if [[ $( aws --region ${awsRegion} lambda list-functions | jq -r '.Functions[].FunctionName' | egrep -i remotecurl | wc -l ) -ge 1 ]]; then
      aws --region ${awsRegion} lambda list-functions | jq -r '.Functions[].FunctionName' | egrep -i remotecurl | while read lambdaName
      do
  		  lambdaState=$( aws --region ${awsRegion} lambda get-function --function-name ${lambdaName} | jq -r '.Configuration.State' )
        if [[ ${lambdaState} == "Inactive" ]]; then
          echo "${acctNum},${acctName},${awsRegion},${lambdaName},${lambdaState}"
        fi
      done
    fi
  done
done

