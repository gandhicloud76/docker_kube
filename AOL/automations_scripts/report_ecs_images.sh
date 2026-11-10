#!/usr/bin/sh 

set +x

#__author__ = 'anildalli'


# variables
prjHome=$(pwd); export prjHome
prjOut=${prjHome}/output; export prjOut
currentDt=$( date '+%Y-%m-%d' )
jenkinsIPaddress=$( hostname -I | awk '{print $1}' )


# called while building HTML page
header() {
cat<<-EOF
<head>
<script src="https://ajax.googleapis.com/ajax/libs/jquery/1.11.2/jquery.min.js" type="text/javascript"></script>
<link rel="stylesheet" type="text/css" href="https://cdn.datatables.net/1.11.2/css/jquery.dataTables.css">
<script type="text/javascript" charset="utf8" src="https://cdn.datatables.net/1.11.2/js/jquery.dataTables.js"></script>

<script>
\$(document).ready( function () {
    var indexLastColumn = \$("#myTable").find('tr')[0].cells.length-1;
    \$('#myTable').DataTable({
    "pageLength": 100,
    "order":[[indexLastColumn,'desc']]
    });
} );
</script>
</head>
EOF
}


#images older than N days
image_age_cutoff_days=70
#tasks running more than N days
task_age_cutoff_days=70

mkdir -p ${prjOut}
rm -f ${prjOut}/* 2>/dev/null

cp ${prjHome}/automations/iam_roles.automations.txt ${prjOut}/iam_roles.txt

echo "# project-home      : ${prjHome}"
echo "# role-session-name : ${jenkinsIPaddress}"
echo "# current-timestamp : $( date '+%Y-%m-%d %H:%M')"

for currentAWSRole in ${AWS_ROLE}; do
for awsRegion in ${AWS_REGION}; do

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
    echo "${currentAWSAccount},${currentAWSAccountAlias}" >>${prjOut}/acct_alias.mapping.txt

		echo "################################################################"
		echo "AWS Account: ${currentAWSAccount} - ${currentAWSAccountAlias}"
		echo "################################################################"
    echo "## awsRegion         : ${awsRegion}"


		#
		#
		
		ecs_clusters=$( aws --region ${awsRegion} ecs list-clusters --query 'clusterArns' | jq -r '.[]' )
		ecs_clusters_array=(${ecs_clusters})
		if [ ${#ecs_clusters_array[@]} -ne 0 ]; then
			for cluster_name in ${ecs_clusters_array[@]}; do
        echo "Cluster : ${cluster_name}"
        cluster_name_fmt=$( echo ${cluster_name} | awk -F"/" '{print $NF}' )
				ecs_tasks=$( aws --region ${awsRegion} ecs list-tasks --cluster ${cluster_name} | jq -r '.taskArns[]' )
				ecs_tasks_array=(${ecs_tasks})
				if [ ${#ecs_tasks_array[@]} -ne 0 ]; then
					for task_name in ${ecs_tasks_array[@]}; do
            echo "  Task : ${task_name}"
            task_name_fmt=$( echo ${task_name} | awk -F"/" '{print $NF}' )
						task_group=$( aws --region ${awsRegion} ecs describe-tasks --cluster ${cluster_name} --tasks ${task_name} | jq -r '.tasks[].group' | sed "s/service://g" )
            
            task_image_imagedigest=$(aws --region ${awsRegion} ecs describe-tasks --cluster ${cluster_name} --tasks ${task_name} | jq -r '.tasks[].containers[] | {image,imageDigest}' | sed "s/\"//g" | sed "s/ //g" | sed "s/image://g" | sed "s/imageDigest://g" | sed "s/^{//g" | sed "s/}$//g" | egrep -v "^$" | tr '\n' ' ' | sed "s/, /,/g" )

            task_image_imagedigest_array=(${task_image_imagedigest})


            #
            #
            #
            #task_start_time_epc=$( aws --region ${awsRegion} ecs describe-tasks --cluster ${cluster_name} --tasks ${task_name} | jq -r '.tasks[].createdAt' | awk -F'.' '{print $1}' )
            #task_start_time=$( date -d @${task_start_time_epc} '+%Y-%m-%d %H:%S' )
            task_start_time=$( aws --region ${awsRegion} ecs describe-tasks --cluster ${cluster_name} --tasks ${task_name} | jq -r '.tasks[].createdAt' | awk -F'.' '{print $1}' | sed "s/T/ /g" )
            task_start_time_epc=$( date -d"${task_start_time}" '+%s' )
            current_epc=$( date '+%s' )
            task_age_epc=$( echo "${current_epc} - ${task_start_time_epc}" | bc -l )
            task_age_days=$( echo "${task_age_epc}/3600/24" | bc )
            task_age_hrs=$( echo "${task_age_epc}/3600%24" | bc )
            if [[ ${task_age_days} -eq 0 ]]; then
              if [[ ${task_age_hrs} -eq 0 ]]; then
                task_age=$( echo "< 1 hr" )
              else
                task_age=$( echo "${task_age_hrs}+ hrs" )
              fi 
            else
              task_age=$( echo "${task_age_days}+ days" )
            fi
            if [[ ${task_age_days} -ge ${task_age_cutoff_days} ]]; then
              task_age_flag=1
            else
              task_age_flag=0
            fi

            task_cpu=$( aws --region ${awsRegion} ecs describe-tasks --cluster ${cluster_name} --tasks ${task_name} | jq -r '.tasks[].cpu' )
            task_memory=$( aws --region ${awsRegion} ecs describe-tasks --cluster ${cluster_name} --tasks ${task_name} | jq -r '.tasks[].memory' )

            for task_image_imagedigest_line in ${task_image_imagedigest_array[@]}; do
              task_image=$( echo ${task_image_imagedigest_line} | awk -F"," '{print $1}' | awk -F"@" '{print $1}' )
              task_imagedigest=$( echo ${task_image_imagedigest_line} | awk -F"," '{print $2}' )

              if [[ -z ${task_imagedigest} ]]; then
                task_imagedigest="NotFound"
              fi

              ##
              ## get col values reading from ECS
              ##
							#AWS Account Number
							#AWS Account Name
              #AWS Region
							#Cluster Name
							#Task Group (Service)
							#Task ID
							#Task Start Time
							#Task Age
							#Task CPU
							#Task Memory
							#Task Image
							#Task Image Digest
              
              echo "${currentAWSAccount},${currentAWSAccountAlias},${awsRegion},${cluster_name_fmt},${task_group},${task_name_fmt},${task_start_time},${task_age},${task_age_flag},${task_cpu},${task_memory},${task_image},${task_imagedigest}" >>${prjOut}/report.ecs.a.csv

            done
					done
				fi
			done
    fi		
	else
		echo "ERROR: AssumeRole operation"
	fi
  
	rm -f awscre-${currentAWSAccount} 2>/dev/null
done
# end of loop for AWS Roles
done
# end of loop for AWS Regions


### Get data from ECR
cat ${prjOut}/report.ecs.a.csv | awk -F',' '{print $(NF-1)","$NF}' | egrep -v "NotFound" | sort -u >${prjOut}/report.ecs.b.images_uniq.csv

cat ${prjOut}/report.ecs.b.images_uniq.csv | while read ecr_line
do
  ecr_image=$( echo ${ecr_line} | awk -F',' '{print $1}' | awk -F':' '{print $1}' )
  ecr_acct_num=$( echo ${ecr_image} | awk -F'.' '{print $1}' )
  ecr_region=$( echo ${ecr_image} | awk -F'.' '{print $4}' )
  ecr_repo_name=$( echo ${ecr_image} | awk -F':' '{print $1}' | awk -F'/' '{$1=""; print $0}' | sed "s/^ //g" | tr ' ' '/' )
  ecr_image_digest=$( echo ${ecr_line} | awk -F',' '{print $2}' )
  ecr_role=$( cat ${prjOut}/iam_roles.txt | egrep ":${ecr_acct_num}:role" | head -1 )
  if [[ -z ${ecr_role} ]]; then
    echo "Error: Did not find the ECR role"
    exit 1
  fi

  echo "${ecr_acct_num},${ecr_region},${ecr_repo_name},${ecr_image},${ecr_image_digest},${ecr_role}"
done >${prjOut}/report.ecs.b.images_uniq.expand.csv

### 
cat ${prjOut}/report.ecs.b.images_uniq.expand.csv | awk -F',' '{print $1","$2","$NF}' | sort -u >${prjOut}/report.ecs.c.ecr_acct_roles.csv

cat ${prjOut}/report.ecs.c.ecr_acct_roles.csv | while read ecr_role_line
do
  ecr_acct_num=$( echo ${ecr_role_line} | awk -F',' '{print $1}' )
  ecr_region=$( echo ${ecr_role_line} | awk -F',' '{print $2}' )
  ecr_role=$( echo ${ecr_role_line} | awk -F',' '{print $3}' )
   
  # assume role to read ECR info
  unset AWS_ACCESS_KEY_ID
  unset AWS_SECRET_ACCESS_KEY
  unset AWS_SECURITY_TOKEN

  aws sts assume-role --region ${ecr_region} --role-arn ${ecr_role} --role-session-name ${jenkinsIPaddress} | \
    grep -w 'AccessKeyId\|SecretAccessKey\|SessionToken' | \
    sed 's/\"//g;s/\,//;s/ //g' > awscre-${ecr_acct_num} ;\

  export AWS_ACCESS_KEY_ID=$( grep AccessKeyId awscre-${ecr_acct_num} | awk -F':' '{print $2}' );\
  export AWS_SECRET_ACCESS_KEY=$( grep SecretAccessKey awscre-${ecr_acct_num} | awk -F':' '{print $2}' );\
  export AWS_SECURITY_TOKEN=$( grep SessionToken awscre-${ecr_acct_num} | awk -F':' '{print $2}' );\

  cat ${prjOut}/report.ecs.b.images_uniq.expand.csv | egrep "^${ecr_acct_num},${ecr_region}," | sort -u | while read ecr_line
  do
    ecr_repo_name=$( echo ${ecr_line} | awk -F',' '{print $3}' )
    ecr_image_digest=$( echo ${ecr_line} | awk -F',' '{print $5}' )

    #ecr_image_push_time_epc=$( aws --region ${ecr_region} ecr describe-images  --repository-name ${ecr_repo_name} --image-ids imageDigest="${ecr_image_digest}" --output json 2>/dev/null | jq -r '.imageDetails[].imagePushedAt' | awk -F'.' '{print $1}' )
    ecr_image_push_time=$( aws --region ${ecr_region} ecr describe-images  --repository-name ${ecr_repo_name} --image-ids imageDigest="${ecr_image_digest}" --output json 2>/dev/null | jq -r '.imageDetails[].imagePushedAt' | awk -F'.' '{print $1}' | sed "s/T/ /g" )
    ecr_image_push_time_epc=$( date -d"${ecr_image_push_time}" '+%s' )


    if [[ -z ${ecr_image_push_time_epc} ]]; then
      ecr_image_push_time="Image-Not-Present"
      ecr_image_age="Image-Not-Present"
      ecr_image_age_flag=1
    else
      #ecr_image_push_time=$( date -d @${ecr_image_push_time_epc} '+%Y-%m-%d %H:%S' )
      current_epc=$( date '+%s' )
      ecr_image_age_epc=$( echo "${current_epc} - ${ecr_image_push_time_epc}" | bc -l )
      ecr_image_age_days=$( echo "${ecr_image_age_epc}/3600/24" | bc )
      ecr_image_age_hrs=$( echo "${ecr_image_age_epc}/3600%24" | bc )
      if [[ ${ecr_image_age_days} -eq 0 ]]; then
        if [[ ${ecr_image_age_hrs} -eq 0 ]]; then
          ecr_image_age=$( echo "< 1 hr" )
        else
          ecr_image_age=$( echo "${ecr_image_age_hrs}+ hrs" )
        fi
      else
        ecr_image_age=$( echo "${ecr_image_age_days}+ days" )
      fi
      if [[ ${ecr_image_age_days} -ge ${image_age_cutoff_days} ]]; then
        ecr_image_age_flag=1
      else
        ecr_image_age_flag=0
      fi
    fi

    echo "${ecr_acct_num},${ecr_region},${ecr_image_digest},${ecr_image_push_time},${ecr_image_age},${ecr_image_age_flag}" >>${prjOut}/report.ecs.c.ecr_image_age.csv
  done
done

##  ##
##  ## get 2 more cols reading from ECR
##  ##
##  #Task Image Push Time
##	#Task Image Age
##  #
##
if [[ ! -s ${prjOut}/report.ecs.a.csv ]]; then
  echo "Error: File not found ${prjOut}/report.ecs.a.csv"
fi
cat ${prjOut}/report.ecs.a.csv | while read rpt_line
do
  ecr_image=$( echo ${rpt_line} | awk -F',' '{print $(NF-1)}' | awk -F':' '{print $1}' )
  ecr_acct_num=$( echo ${ecr_image} | awk -F'.' '{print $1}' )
  ecr_region=$( echo ${ecr_image} | awk -F'.' '{print $4}' )
  image_digest=$( echo ${rpt_line} | awk -F"," '{print $NF}' )
  if [[ ${image_digest} == "NotFound" ]]; then
    image_pushed_at="NA"
    image_age="NA"
    image_age_flag=1
  else
    image_pushed_at=$( cat ${prjOut}/report.ecs.c.ecr_image_age.csv | egrep "${ecr_acct_num},${ecr_region},${image_digest}," | awk -F',' '{print $4}' )
    image_age=$( cat ${prjOut}/report.ecs.c.ecr_image_age.csv | egrep "${ecr_acct_num},${ecr_region},${image_digest}," | awk -F',' '{print $5}' )
    image_age_flag=$( cat ${prjOut}/report.ecs.c.ecr_image_age.csv | egrep "${ecr_acct_num},${ecr_region},${image_digest}," | awk -F',' '{print $6}' )
  fi

  echo "${rpt_line},${image_pushed_at},${image_age},${image_age_flag}" >>${prjOut}/report.csv
done


cat ${prjOut}/report.csv | while read r_line
do
  echo "${r_line}" | awk -F',' '{print $1","$2","$3","$4","$5","$6","$7","$8","$9","$10","$11}' >>${prjOut}/report.tasks_info.tmp.csv
  image_age_flag=$( echo "${r_line}" | awk -F',' '{print $NF}' )
  if [[ ${image_age_flag} -eq 1 ]]; then
    image_age=$( echo "${r_line}" | awk -F',' '{print $(NF-1)}' )
    if [[ "${image_age}" == "Image-Not-Present" ]]; then
      action="Only Redeploy"
    elif [[ "${image_age}" == "NA" ]]; then
      action="Review"
    else
      action="Build and deploy"
    fi
    echo "${r_line}" | awk -F',' '{print $1","$2","$3","$4","$5","$6","$7","$12","$13","$14","$15}' | sed "s/$/,${action}/g" >>${prjOut}/report.tasks_old_images.csv
  fi
  echo "${r_line}" | awk -F',' '{print $1","$2","$3","$4","$5","$6","$7","$12","$13","$14","$15","$16}' >>${prjOut}/report.tasks_all_images.csv
done
cat ${prjOut}/report.tasks_info.tmp.csv | sort -u >${prjOut}/report.tasks_info.csv
cat ${prjOut}/report.tasks_old_images.csv | egrep "742442504506.dkr.ecr." >${prjOut}/report.tasks_old_images.coredev.csv

# Summary Reports

#cat ${prjOut}/report.tasks_all_images.csv | egrep "1$" | awk -F',' '{print $8}'| awk -F':' '{print $1}' | sort -u | awk -F".com/" '{print $1"."$2}' | awk -F'.' '{print $1","$4","$NF}' | sort -u >${prjOut}/report.summary.ecr_repos_with_old_images.csv

cat ${prjOut}/report.tasks_all_images.csv | egrep "1$" | awk -F',' '{print $8","$(NF-2)}' | while read img_line
do
  img_flat=$( echo ${img_line} | awk -F',' '{print $1}' | awk -F':' '{print $1}' | awk -F".com/" '{print $1"."$2}' | awk -F'.' '{print $1","$4","$NF}' )
  img_info=$( echo ${img_line} | awk -F',' '{print $2}' )
  echo "${img_flat},${img_info}"
done | sort -k1 -k2 -k3 -t',' >${prjOut}/report.summary.ecr_repos_with_old_images.tmp.csv

cat ${prjOut}/report.summary.ecr_repos_with_old_images.tmp.csv | awk -F',' '{print $1","$2","$3","}' | sort -u | while read repo_line
do
  repo_img_info=$( cat ${prjOut}/report.summary.ecr_repos_with_old_images.tmp.csv | egrep "${repo_line}" | awk -F',' '{print $NF}' | sort -u | tr '\n' '#' | sed "s/#$//g" | sed "s/#/  /g" )
  echo "${repo_line}${repo_img_info}"
done >${prjOut}/report.summary.ecr_repos_with_old_images.csv

cat ${prjOut}/report.summary.ecr_repos_with_old_images.csv | egrep "742442504506" >${prjOut}/report.summary.ecr_repos_with_old_images.coredev.csv


cat ${prjOut}/report.tasks_info.csv | awk -F',' '{print $1","$2","$3","$4","$5}' | uniq -c | awk '{print $2","$1}' >${prjOut}/report.summary.num_tasks.csv


# Create HTML report
echo "<html>
`header`
<h3>ECS Tasks Info - ${currentDt}</h3>
<body>
<table border="1">
<tr>
<th bgcolor="lightblue">AWS-Account</th>
<th bgcolor="lightblue">AWS-Account Name</th>
<th bgcolor="lightblue">AWS-Region</th>
<th bgcolor="lightblue">Cluster-Name</th>
<th bgcolor="lightblue">Service-Name</th>
<th bgcolor="lightblue">Task-ID</th>
<th bgcolor="lightblue">Task-Start-Time(UTC)</th>
<th bgcolor="lightblue">Task-Age</th>
<th bgcolor="lightblue">CPU</th>
<th bgcolor="lightblue">Memory</th>
</tr>"	>${prjOut}/report.tasks_info.html

if [ -s ${prjOut}/report.tasks_info.csv ]; then
	cat ${prjOut}/report.tasks_info.csv | while read x
	do

    row_col=""
		col1=$( echo $x | awk -F"," '{print $1}' )
		col2=$( echo $x | awk -F"," '{print $2}' )
		col3=$( echo $x | awk -F"," '{print $3}' )
		col4=$( echo $x | awk -F"," '{print $4}' )
		col5=$( echo $x | awk -F"," '{print $5}' )
		col6=$( echo $x | awk -F"," '{print $6}' )
		col7=$( echo $x | awk -F"," '{print $7}' )
		col8=$( echo $x | awk -F"," '{print $8}' )
		col9=$( echo $x | awk -F"," '{print $9}' )
    if [[ ${col9} -eq 1 ]]; then row_col="red"; fi
		col10=$( echo $x | awk -F"," '{print $10}' )
		col11=$( echo $x | awk -F"," '{print $11}' )

		echo "<tr>
		<td><font color=${row_col}>${col1}</font></td>
		<td><font color=${row_col}>${col2}</font></td>
		<td><font color=${row_col}>${col3}</font></td>
		<td><font color=${row_col}>${col4}</font></td>
		<td><font color=${row_col}>${col5}</font></td>
		<td><font color=${row_col}>${col6}</font></td>
		<td><font color=${row_col}>${col7}</font></td>
		<td><font color=${row_col}>${col8}</font></td>
		<td><font color=${row_col}>${col10}</font></td>
		<td><font color=${row_col}>${col11}</font></td>
		</tr>"	>>${prjOut}/report.tasks_info.html
	done
else
	echo "<tr>Report NA</tr>"
fi
echo "</table></body></html>"	>>${prjOut}/report.tasks_info.html


# Create HTML report
echo "<html>
`header`
<h3>ECS Tasks running All Images - ${currentDt}</h3>
<body>
<table border="1">
<tr>
<th bgcolor="lightblue">AWS-Account</th>
<th bgcolor="lightblue">AWS-Account Name</th>
<th bgcolor="lightblue">AWS-Region</th>
<th bgcolor="lightblue">Cluster-Name</th>
<th bgcolor="lightblue">Service-Name</th>
<th bgcolor="lightblue">Task-ID</th>
<th bgcolor="lightblue">Task-Start-Time(UTC)</th>
<th bgcolor="lightblue">Task-Image</th>
<th bgcolor="lightblue">Task-ImageDigest</th>
<th bgcolor="lightblue">Image-Pushed-At</th>
<th bgcolor="lightblue">Image-Age</th>
</tr>"	>${prjOut}/report.tasks_all_images.html

if [ -s ${prjOut}/report.tasks_all_images.csv ]; then
	cat ${prjOut}/report.tasks_all_images.csv | while read x
	do

    row_col=""
		col1=$( echo $x | awk -F"," '{print $1}' )
		col2=$( echo $x | awk -F"," '{print $2}' )
		col3=$( echo $x | awk -F"," '{print $3}' )
		col4=$( echo $x | awk -F"," '{print $4}' )
		col5=$( echo $x | awk -F"," '{print $5}' )
		col6=$( echo $x | awk -F"," '{print $6}' )
		col7=$( echo $x | awk -F"," '{print $7}' )
		col8=$( echo $x | awk -F"," '{print $8}' )
		col9=$( echo $x | awk -F"," '{print $9}' )
		col10=$( echo $x | awk -F"," '{print $10}' )
		col11=$( echo $x | awk -F"," '{print $11}' )
		col12=$( echo $x | awk -F"," '{print $12}' )
    if [[ ${col12} -eq 1 ]]; then row_col="red"; fi
		echo "<tr>
		<td><font color=${row_col}>${col1}</font></td>
		<td><font color=${row_col}>${col2}</font></td>
		<td><font color=${row_col}>${col3}</font></td>
		<td><font color=${row_col}>${col4}</font></td>
		<td><font color=${row_col}>${col5}</font></td>
		<td><font color=${row_col}>${col6}</font></td>
		<td><font color=${row_col}>${col7}</font></td>
		<td><font color=${row_col}>${col8}</font></td>
		<td><font color=${row_col}>${col9}</font></td>
		<td><font color=${row_col}>${col10}</font></td>
		<td><font color=${row_col}>${col11}</font></td>
		</tr>"	>>${prjOut}/report.tasks_all_images.html
	done
else
	echo "<tr>Report NA</tr>"
fi
echo "</table></body></html>"	>>${prjOut}/report.tasks_all_images.html

# Create HTML report
echo "<html>
`header`
<h3>ECS Tasks running Old Images - ${currentDt}</h3>
<body>
<table border="1">
<tr>
<th bgcolor="lightblue">AWS-Account</th>
<th bgcolor="lightblue">AWS-Account Name</th>
<th bgcolor="lightblue">AWS-Region</th>
<th bgcolor="lightblue">Cluster-Name</th>
<th bgcolor="lightblue">Service-Name</th>
<th bgcolor="lightblue">Task-ID</th>
<th bgcolor="lightblue">Task-Start-Time(UTC)</th>
<th bgcolor="lightblue">Task-Image</th>
<th bgcolor="lightblue">Task-ImageDigest</th>
<th bgcolor="lightblue">Image-Pushed-At</th>
<th bgcolor="lightblue">Image-Age</th>
<th bgcolor="lightblue">Action Suggested</th>
</tr>"	>${prjOut}/report.tasks_old_images.html

if [ -s ${prjOut}/report.tasks_old_images.coredev.csv ]; then
	cat ${prjOut}/report.tasks_old_images.coredev.csv | while read x
	do

    row_col=""
		col1=$( echo $x | awk -F"," '{print $1}' )
		col2=$( echo $x | awk -F"," '{print $2}' )
		col3=$( echo $x | awk -F"," '{print $3}' )
		col4=$( echo $x | awk -F"," '{print $4}' )
		col5=$( echo $x | awk -F"," '{print $5}' )
		col6=$( echo $x | awk -F"," '{print $6}' )
		col7=$( echo $x | awk -F"," '{print $7}' )
		col8=$( echo $x | awk -F"," '{print $8}' )
		col9=$( echo $x | awk -F"," '{print $9}' )
		col10=$( echo $x | awk -F"," '{print $10}' )
		col11=$( echo $x | awk -F"," '{print $11}' )
		col12=$( echo $x | awk -F"," '{print $12}' )
    row_col="red"
		echo "<tr>
		<td><font color=${row_col}>${col1}</font></td>
		<td><font color=${row_col}>${col2}</font></td>
		<td><font color=${row_col}>${col3}</font></td>
		<td><font color=${row_col}>${col4}</font></td>
		<td><font color=${row_col}>${col5}</font></td>
		<td><font color=${row_col}>${col6}</font></td>
		<td><font color=${row_col}>${col7}</font></td>
		<td><font color=${row_col}>${col8}</font></td>
		<td><font color=${row_col}>${col9}</font></td>
		<td><font color=${row_col}>${col10}</font></td>
		<td><font color=${row_col}>${col11}</font></td>
		<td><font color=${row_col}>${col12}</font></td>
		</tr>"	>>${prjOut}/report.tasks_old_images.html
	done
else
	echo "<tr>Report NA</tr>"
fi
echo "</table></body></html>"	>>${prjOut}/report.tasks_old_images.html

# Create HTML report
echo "<html>
`header`
<h3>ECS Num of Tasks running - ${currentDt}</h3>
<body>
<table border="1">
<tr>
<th bgcolor="lightblue">AWS-Account</th>
<th bgcolor="lightblue">AWS-Account Name</th>
<th bgcolor="lightblue">AWS-Region</th>
<th bgcolor="lightblue">Cluster-Name</th>
<th bgcolor="lightblue">Service-Name</th>
<th bgcolor="lightblue">Num_of_Tasks</th>
</tr>"  >${prjOut}/report.summary.num_tasks.html

if [ -s ${prjOut}/report.summary.num_tasks.csv ]; then
  cat ${prjOut}/report.summary.num_tasks.csv | while read x
  do

    col1=$( echo $x | awk -F"," '{print $1}' )
    col2=$( echo $x | awk -F"," '{print $2}' )
    col3=$( echo $x | awk -F"," '{print $3}' )
    col4=$( echo $x | awk -F"," '{print $4}' )
    col5=$( echo $x | awk -F"," '{print $5}' )
    col6=$( echo $x | awk -F"," '{print $6}' )
    echo "<tr>
    <td>${col1}</td>
    <td>${col2}</td>
    <td>${col3}</td>
    <td>${col4}</td>
    <td>${col5}</td>
    <td>${col6}</td>
    </tr>"  >>${prjOut}/report.summary.num_tasks.html
  done
else
  echo "<tr>Report NA</tr>"
fi
echo "</table></body></html>" >>${prjOut}/report.summary.num_tasks.html

# Create HTML report
echo "<html>
`header`
<h3>ECR Repositories having old images for running ECS Tasks - ${currentDt}</h3>
<body>
<table border="1">
<tr>
<th bgcolor="lightblue">ECR-AWS-Account</th>
<th bgcolor="lightblue">ECR-AWS-Account-Name</th>
<th bgcolor="lightblue">ECR-Region</th>
<th bgcolor="lightblue">ECS tasks are running with either deleted images or old images (older than ${image_age_cutoff_days} days) from below repositories</th>
<th bgcolor="lightblue">Status or Creation Time of the Image used by the running Task(s)</th>
</tr>"  >${prjOut}/report.summary.ecr_repos_with_old_images.html

if [ -s ${prjOut}/report.summary.ecr_repos_with_old_images.coredev.csv ]; then
  cat ${prjOut}/report.summary.ecr_repos_with_old_images.coredev.csv | while read x
  do

    col1=$( echo $x | awk -F"," '{print $1}' )
    col2=$( cat ${prjOut}/acct_alias.mapping.txt | egrep "^${col1}," | awk -F"," '{print $2}' | sort -u )
    col3=$( echo $x | awk -F"," '{print $2}' )
    col4=$( echo $x | awk -F"," '{print $3}' )
    col5=$( echo $x | awk -F"," '{print $4}' )
    echo "<tr>
    <td>${col1}</td>
    <td>${col2}</td>
    <td>${col3}</td>
    <td>${col4}</td>
    <td>${col5}</td>
    </tr>"  >>${prjOut}/report.summary.ecr_repos_with_old_images.html
  done
else
  echo "<tr>Report NA</tr>" >>${prjOut}/report.summary.ecr_repos_with_old_images.html
fi
echo "</table><br><br>" >>${prjOut}/report.summary.ecr_repos_with_old_images.html

echo "<h3><a href="https://jenkins.legacy.obieng.com:8443/view/Automations/job/Report-ECS-Tasks-ECR-Images-Age-Audit/ECS-Tasks-using-Old-Images-HTML-Report/">*** Click here: Check details on repositories listed above for running tasks/images, and suggested action</a></h3></body></html>" >>${prjOut}/report.summary.ecr_repos_with_old_images.html

echo "<br><br>" >>${prjOut}/report.summary.ecr_repos_with_old_images.html

echo "<h3><a href="https://jenkins.legacy.obieng.com:8443/view/Automations/job/Report_ECR_Old_Images/ECR-REPO-OLD-IMAGES-HTML-Report/">*** Click here: Check repositories having images older than 75 days. The old images in the repositories need to be reviewed carefully before deletion</a></h3></body></html>" >>${prjOut}/report.summary.ecr_repos_with_old_images.html

echo "<br><br>" >>${prjOut}/report.summary.ecr_repos_with_old_images.html

##
touch /tmp/report_ecs_images.done
set -x


