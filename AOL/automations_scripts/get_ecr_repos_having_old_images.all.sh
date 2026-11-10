#!/usr/bin/sh 

set +x
testHome=$(pwd); export testHome
cutoff_days=70
cutoff_days_epc=$( date -d "-${cutoff_days} days" '+%s' )
cutoff_days_critical=83
cutoff_days_critical_epc=$( date -d "-${cutoff_days_critical} days" '+%s' )

testOut=${testHome}/output; export testOut
mkdir -p ${testOut}
rm -f ${testOut}/report*csv  2>/dev/null

for curr_aws_role in ${AWS_ROLE}; do

  curr_aws_acct=$( echo ${curr_aws_role} | awk -F":" '{print $5}' )
  
  unset AWS_ACCESS_KEY_ID
  unset AWS_SECRET_ACCESS_KEY
  unset AWS_SECURITY_TOKEN

  aws sts assume-role --region us-east-1 --role-arn ${curr_aws_role} --role-session-name jenkins 2>awscre-${curr_aws_acct}.err | \
      grep -w 'AccessKeyId\|SecretAccessKey\|SessionToken' | \
      sed 's/\"//g;s/\,//;s/ //g' > awscre-${curr_aws_acct} ;\

  if [[ -s awscre-${curr_aws_acct}.err ]]; then
    if [[ $( cat awscre-${curr_aws_acct}.err | egrep "RegionDisabledException" | wc -l ) -eq 1 ]]; then
      echo "Warning: RegionDisabledException, skip"
      cat awscre-${curr_aws_acct}.err
      continue
    fi
  fi
      

  export AWS_ACCESS_KEY_ID=$( grep AccessKeyId  awscre-${curr_aws_acct} | awk -F':' '{print $2}' );\
  export AWS_SECRET_ACCESS_KEY=$( grep SecretAccessKey awscre-${curr_aws_acct} | awk -F':' '{print $2}' );\
  export AWS_SECURITY_TOKEN=$( grep SessionToken awscre-${curr_aws_acct} | awk -F':' '{print $2}' );\
  
  ACCT_NUM=$( aws --region us-east-1 sts get-caller-identity | jq -r '.Account' )
  ACCT_ALIAS=$( aws --region us-east-1 iam list-account-aliases | jq -r '.AccountAliases[]' )
  
  for region in ${AWS_REGION}; do
  
  repo_names=$( aws --region ${region} ecr describe-repositories --output json | jq -r '.repositories[].repositoryName' )
  #echo $repo_names
  repo_names_array=(${repo_names})
  #repo_names_array=("aol_obi/apidocs" "aol_obi/auth")
  if [ ${#repo_names_array[@]} -ne 0 ]; then
	for repo_name in ${repo_names_array[@]}; do
      echo "### ${ACCT_NUM} --- ${region} --- ${repo_name}"
      img_cnt=0
      old_img_cnt=0
      img_cnt_critical=0
      old_img_cnt_critical=0
      rm ${testOut}/report.tmp.csv  2>/dev/null
      aws ecr describe-images --region ${region} --repository-name "${repo_name}" | jq -r '.imageDetails[].imagePushedAt' | awk -F'.' '{print $1}' | sed "s/T/ /g" | while read img_push_time
      do
        img_push_time_epc=$( date -d"${img_push_time}" '+%s' )
        # WARNING - send email
        if [[ ${img_push_time_epc} -lt ${cutoff_days_epc} ]]; then
          old_img_cnt=$( echo "${old_img_cnt} + 1" | bc )
        fi
        img_cnt=$( echo "${img_cnt} + 1" | bc )
        echo "${ACCT_NUM},${ACCT_ALIAS},${region},${repo_name},${img_cnt},${old_img_cnt}" >${testOut}/report.tmp.csv
        # CRITICAL - send slack alert
        if [[ ${img_push_time_epc} -lt ${cutoff_days_critical_epc} ]]; then
          old_img_cnt_critical=$( echo "${old_img_cnt_critical} + 1" | bc )
        fi
        img_cnt_critical=$( echo "${img_cnt_critical} + 1" | bc )
        echo "${ACCT_NUM},${ACCT_ALIAS},${region},${repo_name},${img_cnt_critical},${old_img_cnt_critical}" >${testOut}/report.tmp_critical.csv
      done
      # WARNING - send email
      if [[ ! -s ${testOut}/report.tmp.csv ]]; then
        echo "${ACCT_NUM},${ACCT_ALIAS},${region},${repo_name},0,0" >${testOut}/report.tmp.csv
      fi
      cat ${testOut}/report.tmp.csv  >>${testOut}/report.csv 
      # CRITICAL - send slack alert
      if [[ ! -s ${testOut}/report.tmp_critical.csv ]]; then
        echo "${ACCT_NUM},${ACCT_ALIAS},${region},${repo_name},0,0" >${testOut}/report.tmp_critical.csv
      fi
      cat ${testOut}/report.tmp_critical.csv  >>${testOut}/report.critical.csv 
    done
  fi
  
  done
done
set -x


set +x
cat ${testOut}/report.csv | egrep -v ",0$" >${testOut}/report.old.csv
cat ${testOut}/report.critical.csv | egrep -v ",0$" >${testOut}/report.critical.old.csv
echo "<html>
<h3>List of Repositories having images OLDER than ${cutoff_days} days</h3>
<body>
<table border="1">
<tr>
<th bgcolor="lightblue">AWS Account</th>
<th bgcolor="lightblue">AWS Account Name</th>
<th bgcolor="lightblue">AWS Region</th>
<th bgcolor="lightblue">Repository Name</th>
<th bgcolor="lightblue">Number of Images </th>
<th bgcolor="lightblue">Number of OLD Images (older than ${cutoff_days} days)</th>
</tr>"	>${testOut}/report.html

if [ -s ${testOut}/report.old.csv ]; then
	cat ${testOut}/report.old.csv | while read x
	do
		col1=$( echo $x | awk -F"," '{print $1}' )
		col2=$( echo $x | awk -F"," '{print $2}' )
    col3=$( echo $x | awk -F"," '{print $3}' )
		col4=$( echo $x | awk -F"," '{print $4}' )
		col5=$( echo $x | awk -F"," '{print $5}' )
    col6=$( echo $x | awk -F"," '{print $6}' )
    fg_color=''
		if [[ ${col6} -ge 1 ]]; then
        fg_color='red'
    fi
        
		echo "<tr style=\"color: ${fg_color};\">
		<td>${col1}</td>
		<td>${col2}</td>
    <td>${col3}</td>
		<td>${col4}</td>
    <td>${col5}</td>
    <td>${col6}</td>
		</tr>"	>>${testOut}/report.html
	done
else
	echo "<tr>Report NA</tr>"
fi
echo "</table></body></html>"	>>${testOut}/report.html



# if the list has any repository having image older than cut off days then the job fails and sends email
if [ -s ${testOut}/report.old.csv ]; then
  if [[ $( cat ${testOut}/report.old.csv | egrep "obi" | wc -l ) -ne 0 ]]; then
    echo "INFO: OBI Repositories"
    cat ${testOut}/report.old.csv | egrep "obi"
    echo "ERROR: We have $( cat ${testOut}/report.old.csv | egrep "obi" | wc -l ) repositories (maintained by OBI team) having images older than ${cutoff_days} days. Send Email."
    exit 1
  else
    echo "INFO: We have $( cat ${testOut}/report.old.csv | egrep "obi" | wc -l ) repositories (maintained by OBI team) having images older than ${cutoff_days} days."
  fi
else
  echo "INFO: nothing to alarm"
fi



set -x
