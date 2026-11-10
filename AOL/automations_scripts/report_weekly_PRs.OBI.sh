#!/usr/bin/sh

## __author__ = 'Anil Reddy Dalli'
##
## PR weekly summary:  Total Open, new open, closed (Last 4 weeks)
## Scan through all active repositories of Github and Gitlab to generate the report
## [+] Active repositories are those where archived state is false 


prjHome=$(pwd)
prjTmp="${prjHome}/tmp"
prjOut="${prjHome}/output"

rm -rf ${prjTmp} ${prjOut} 2>/dev/null
mkdir -p ${prjTmp} ${prjOut}

#pr_cutoff_date_epc=$( date -d "-7 days" '+%s' )
# calculate the time taken in seconds
calc_timetaken() {
        if [[ $stepnum == "" ]]; then
                stepnum=0
        fi
        if [[ $epmystarttime == "" ]]; then
                epmystarttime=$( date +%s )
        fi
        epmyendtime=$( date +%s )
        eptimediff=$( expr $epmyendtime - $epmystarttime )
        epmystarttime=$( echo -e $epmyendtime )

        echo -e "\nSTEP# $stepnum time taken : $eptimediff secs\n"
        stepnum=$( expr $stepnum + 1 )
}

github_base_api="https://git.ouryahoo.com/api/v3"
gitlab_base_api="https://scm.obieng.com/api/v4"

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

#
# compute time taken
calc_timetaken

# Below variables are staored as secret text(s) and are used in the Jenkins Build Environment
#github_api_token=""
#gitlab_api_token=""

# get Gitlab active repositories (i.e. archived=false)
#
gitlab_api_repos="${gitlab_base_api}/projects?private_token=${gitlab_api_token}&per_page=100"

curl --head -H 'Content-Type: application/json' "${gitlab_api_repos}"	2>/dev/null >${prjTmp}/repos.head.json
if [[ $( cat ${prjTmp}/repos.head.json | egrep "HTTP/1.1 200 OK" | wc -l | sed "s/ //g" ) -ne 1 ]]; then
	echo "ERROR: Gitlab Curl Failed (gitlab_api_repos). Exit."
    exit 1
fi

reposLastPage=$( cat ${prjTmp}/repos.head.json | egrep "X-Total-Pages:" | awk -F":" '{print $NF}' | sed "s/ //g" | head -1 )
reposLastPage=${reposLastPage//[$'\t\r\n ']}
if [[ -z ${reposLastPage} ]]; then
    reposLastPage=1
fi
i=1
while [[ ${i} -le ${reposLastPage} ]]; do
	curl -H 'Content-Type: application/json' "${gitlab_api_repos}&page=${i}"	2>/dev/null
	i=$( echo ${i} + 1 | bc )
done | sed "s/\]\[/,/g" 	>${prjTmp}/repos.json

repoNamesAll_array=($( cat ${prjTmp}/repos.json | jq '.[].path_with_namespace' | sed "s/\"//g" | sed "s/ //g" | egrep -v "AlexanderLepekhin|PuneetSharma" | sort -d | tr '\n' ' ' ))
repoNamesActive_array=($( cat ${prjTmp}/repos.json | jq '.[] | select( "\(.archived)" == "false" ) | "\(.path_with_namespace)#\(.id)"' | sed "s/\"//g" | sed "s/ //g" | egrep -v "AlexanderLepekhin|PuneetSharma" | sort -d | tr '\n' ' ' ))    

for repoFullNameId in ${repoNamesActive_array[@]}; do
    repoNameId=$( echo "${repoFullNameId}" | awk -F'/' '{print $NF}' )
    repoNamesActive_array_gl+=(${repoNameId})
done
for repoName in ${repoNamesActive_array_gl[@]}; do
    repoNamesActive_array_gl_map+=(${repoName}":gitlab")
done
echo "#########################################################################"
echo "### Gitlab : active repos ${#repoNamesActive_array[@]} (total ${#repoNamesAll_array[@]})"

# get Github active repositories (i.e. archived=false)
#
repoOwner=OBI
github_api_repos="${github_base_api}/orgs/${repoOwner}/repos"

curl --head -H 'Content-Type: application/json' -H "Authorization: Bearer ${github_api_token}" "${github_api_repos}"	2>/dev/null >${prjTmp}/repos.head.json
if [[ $( cat ${prjTmp}/repos.head.json | egrep "HTTP/1.1 200 OK" | wc -l | sed "s/ //g" ) -ne 1 ]]; then
	echo "ERROR: Github Curl Failed (github_api_repos). Exit."
    exit 1
fi
	
reposLastPage=$( cat ${prjTmp}/repos.head.json | egrep "Link:" | egrep "last" | awk -F"/" '{print $NF}' | awk -F">" '{print $1}' | awk -F"=" '{print $NF}' )
if [[ -z ${reposLastPage} ]]; then
    reposLastPage=1
fi
i=1
while [[ ${i} -le ${reposLastPage} ]]; do
	curl -H 'Content-Type: application/json' -H "Authorization: Bearer ${github_api_token}" "${github_api_repos}?page=${i}"	2>/dev/null
	i=$( echo ${i} + 1 | bc )
done | sed "s/\]\[/,/g" 	>${prjTmp}/repos.json
	
repoNamesAll_array=($( cat ${prjTmp}/repos.json | jq '.[].full_name' | sed "s/\"//g" | sort -d | tr '\n' ' ' ))
repoNamesActive_array=($( cat ${prjTmp}/repos.json | jq '.[] | select( "\(.archived)" == "false" ) | "\(.full_name)"' | sed "s/\"//g" | sort -d | tr '\n' ' ' ))
	
for repoFullName in ${repoNamesActive_array[@]}; do
    repoName=$( echo "${repoFullName}" | awk -F"/" '{print $NF}' )
    repoNamesActive_array_gh+=(${repoName})
done
for repoName in ${repoNamesActive_array_gh[@]}; do
    repoNamesActive_array_gh_map+=(${repoName}":github")
done
echo "### Github : active repos ${#repoNamesActive_array[@]} (total ${#repoNamesAll_array[@]})"
echo "#########################################################################"

project_repos_map_array=("${repoNamesActive_array_gl_map[@]}" "${repoNamesActive_array_gh_map[@]}")
echo "### Gitlab+Github : ${#project_repos_map_array[@]} repos to be scanned for open PRs"
echo "#########################################################################"

#
# compute time taken
calc_timetaken

# loop through project repositories and scan for open PRs
#
sl_no=1
for repoNameGitType in ${project_repos_map_array[@]}; do
    repoName=$( echo "${repoNameGitType}" | awk -F':' '{print $1}' | awk -F'#' '{print $1}' )
    gitType=$( echo "${repoNameGitType}" | awk -F':' '{print $2}' )

    if [[ ${gitType} == "github" ]]; then
        base_api="https://git.ouryahoo.com/api/v3"
        api_token=${github_api_token}
    else
        base_api="https://scm.obieng.com/api/v4"
        api_token=${gitlab_api_token}
        gitlab_repo_id=$( echo "${repoNameGitType}" | awk -F':' '{print $1}' | awk -F'#' '{print $NF}' )
	echo "${repoName},${gitlab_repo_id}" >>${prjTmp}/gitlab.repo_repoid.lookup.lst
    fi
    
    if [[ ${gitType} == "github" ]]; then
	github_api_pulls="${base_api}/repos/${repoOwner}/${repoName}/pulls?state=all&per_page=100"

	curl --head -H 'Content-Type: application/json' -H "Authorization: Bearer ${api_token}" "${github_api_pulls}"	2>/dev/null >${prjTmp}/pr.head.json
	if [[ $( cat ${prjTmp}/pr.head.json | egrep "HTTP/1.1 200 OK" | wc -l | sed "s/ //g" ) -ne 1 ]]; then
		echo "ERROR: Github Curl Failed (github_api_pulls). Exit."
    			exit 1
	fi

	reposLastPage=$( cat ${prjTmp}/pr.head.json| egrep "Link:" | egrep "last" | awk -F"/" '{print $NF}' | awk -F">" '{print $1}' | awk -F"=" '{print $NF}' )
	if [[ -z ${reposLastPage} ]]; then
    		reposLastPage=1
        fi
	i=1
        rm -f ${prjTmp}/pr.${repoName}.json
        while [[ ${i} -le ${reposLastPage} ]]; do
		p_out=$( curl -H 'Content-Type: application/json' -H "Authorization: Bearer ${api_token}" "${github_api_pulls}&page=${i}"	2>/dev/null )
            	echo -n ${p_out}
		i=$( echo ${i} + 1 | bc )
	done | sed "s/\]\[/,/g"  >>${prjTmp}/pr.${repoName}.json

       	for key in $( cat ${prjTmp}/pr.${repoName}.json | jq '. | keys | .[]' ); do
       		cat ${prjTmp}/pr.${repoName}.json | jq .[${key}]	>${prjTmp}/pr.key.json
          
          git_pull_title=$( cat ${prjTmp}/pr.key.json | jq '.title' | sed "s/\"//g" | sed "s/,//g" | sed "s/\\\//g" )
          if [[ $( echo ${git_pull_title} | egrep "Pull request for prod release" | wc -l ) -eq 1 ]]; then
            continue
          fi
       		git_pull_url=$( cat ${prjTmp}/pr.key.json | jq '.html_url' | sed "s/\"//g" )
       		git_pull_created_at=$( cat ${prjTmp}/pr.key.json | jq '.created_at' | sed "s/\"//g" | sed "s/T/ /g" | sed "s/Z//g" | awk -F'.' '{print $1}' )
       		git_pull_closed_at=$( cat ${prjTmp}/pr.key.json | jq '.closed_at' | sed "s/\"//g" | sed "s/T/ /g" | sed "s/Z//g" | awk -F'.' '{print $1}' )
       		git_pull_state=$( cat ${prjTmp}/pr.key.json | jq '.state' | sed "s/\"//g" )
    		
       		echo "${repoName},${git_pull_url},${git_pull_created_at},${git_pull_closed_at},${git_pull_state}"	>>${prjTmp}/pr.csv
       	done
    fi
    
    if [[ ${gitType} == "gitlab" ]]; then
	gitlab_api_pulls="${base_api}/projects/${gitlab_repo_id}/merge_requests?state=all&private_token=${api_token}&per_page=100"
        
        	curl --head -H 'Content-Type: application/json' "${gitlab_api_pulls}"	2>/dev/null >${prjTmp}/pr.head.json
	if [[ $( cat ${prjTmp}/pr.head.json | egrep "HTTP/1.1 200 OK" | wc -l | sed "s/ //g" ) -ne 1 ]]; then
		echo "ERROR: Gitlab Curl Failed (gitlab_api_pulls). Exit."
    			exit 1
	fi

	reposLastPage=$( cat ${prjTmp}/pr.head.json | egrep "X-Total-Pages:" | awk -F":" '{print $NF}' | sed "s/ //g" | head -1 )
	reposLastPage=${reposLastPage//[$'\t\r\n ']}
	if [[ -z ${reposLastPage} ]]; then
    			reposLastPage=1
	fi
	i=1
        rm -f ${prjTmp}/pr.${repoName}.json
	while [[ ${i} -le ${reposLastPage} ]]; do
		curl -H 'Content-Type: application/json' "${gitlab_api_pulls}&page=${i}"	2>/dev/null
		i=$( echo ${i} + 1 | bc )
	done | sed "s/\]\[/,/g" 	>${prjTmp}/pr.${repoName}.json
        
       	for key in $( cat ${prjTmp}/pr.${repoName}.json | jq '. | keys | .[]' ); do
       		cat ${prjTmp}/pr.${repoName}.json | jq .[${key}]	>${prjTmp}/pr.key.json
       	
          git_pull_url=$( cat ${prjTmp}/pr.key.json | jq '.web_url' | sed "s/\"//g" )
        	git_pull_created_at=$( cat ${prjTmp}/pr.key.json | jq '.created_at' | sed "s/\"//g" | sed "s/T/ /g" | sed "s/Z//g" | awk -F'.' '{print $1}' )
        	git_pull_closed_at=$( cat ${prjTmp}/pr.key.json | jq '.closed_at' | sed "s/\"//g" | sed "s/T/ /g" | sed "s/Z//g" | awk -F'.' '{print $1}' )
        	git_pull_state=$( cat ${prjTmp}/pr.key.json | jq '.state' | sed "s/\"//g" )
		if [[ ${git_pull_state} == "merged" ]]; then
        		git_pull_closed_at=$( cat ${prjTmp}/pr.key.json | jq '.merged_at' | sed "s/\"//g" | sed "s/T/ /g" | sed "s/Z//g" | awk -F'.' '{print $1}' )
		fi
		if [[ ${git_pull_closed_at} == "null" ]] && [[ ${git_pull_state} != "opened" ]]; then
        		git_pull_closed_at=$( cat ${prjTmp}/pr.key.json | jq '.updated_at' | sed "s/\"//g" | sed "s/T/ /g" | sed "s/Z//g" | awk -F'.' '{print $1}' )
		fi
    		
        	echo "${repoName},${git_pull_url},${git_pull_created_at},${git_pull_closed_at},${git_pull_state}"	>>${prjTmp}/pr.csv
        done
    fi

    num_prs_maxkey=$( cat ${prjTmp}/pr.${repoName}.json | jq '. | keys | .[]' | wc -l )
    echo "${sl_no} / ${#project_repos_map_array[@]} # ${gitType} : ${repoName} : ${num_prs_maxkey}"
    sl_no=$( echo ${sl_no} + 1 | bc )

    #
    # compute time taken
    calc_timetaken

done

cat ${prjTmp}/pr.csv | sed "s/,merged/,closed/g" | awk -F',' '{print $1","$2","$3","$4","$5}' >${prjTmp}/pr.fmt.csv

week_start_dt_tmp=$( date --date='last Thursday' '+%Y-%m-%d' )
week_start_dt_tmp_epc=$( date -d "${week_start_dt_tmp} 00:00:00" '+%s' )

week_end_dt=$( date --date='last Wednesday' '+%Y-%m-%d' )
week_end_dt_epc=$( date -d "${week_end_dt} 23:59:59" '+%s' )
this_week_end_dt=${week_end_dt}
this_week_end_dt_epc=${week_end_dt_epc}

if [[ ${week_start_dt_tmp_epc} -gt ${week_end_dt_epc} ]]; then
        week_start_dt=$( date -d "-7 days ${week_start_dt_tmp}" '+%Y-%m-%d' )
        week_start_dt_epc=$( date -d "${week_start_dt} 00:00:00" '+%s' )
else
        week_start_dt=${week_start_dt_tmp}
        week_start_dt_epc=${week_start_dt_tmp_epc}
fi
this_week_start_dt=${week_start_dt}
this_week_start_dt_epc=${week_start_dt_epc}

num_weeks_for_report=4
this_week=0
while [ ${this_week} -lt ${num_weeks_for_report} ]; do
	week_num_days=$( echo "${this_week} * 7"| bc )
	echo "$( date -d "-${week_num_days} days ${week_start_dt}" '+%Y-%m-%d'),$( date -d "-${week_num_days} days ${week_end_dt}" '+%Y-%m-%d')"
	this_week=$( echo $this_week + 1 | bc )
done >${prjTmp}/report_week_schedule.txt

#
# compute time taken
calc_timetaken

cat ${prjTmp}/report_week_schedule.txt | while read x
do

	echo "###"
	echo "### Running for week : $week_start_dt_epc - $week_end_dt_epc"
	echo "###"

	week_start_dt=$( echo $x | awk -F',' '{print $1}' )
	week_start_dt_epc=$( date -d "${week_start_dt} 00:00:00" '+%s' )

	week_end_dt=$( echo $x | awk -F',' '{print $2}' )
	week_end_dt_epc=$( date -d "${week_end_dt} 23:59:59" '+%s' )

	week_num=$( cat ${prjTmp}/report_week_schedule.txt | egrep -n "${week_start_dt}," | awk -F':' '{print $1}' )
	week_num_tmp=$( echo "${week_num} -1" | bc )
	exclude_week_num_days=$( echo "${week_num_tmp} * 7"| bc )
	
	n=0
	while [ ${n} -lt ${exclude_week_num_days} ]; do
		mydt=$( date -d "-${n} days ${this_week_end_dt}" '+%Y-%m-%d')
		n=$( echo "$n + 1" | bc )
		echo ${mydt}
	done >${prjTmp}/days_to_exclude.lst

	if [[ -f ${prjTmp}/days_to_exclude.lst ]]; then
		touch ${prjTmp}/days_to_exclude.lst
	fi

	cat ${prjTmp}/pr.fmt.csv | egrep ",open" | awk -F',' '{print $1","$2","$3","$5}' | egrep -v -f ${prjTmp}/days_to_exclude.lst >${prjTmp}/pr.total_open.${week_start_dt}.${week_end_dt}.still.full.csv
	rm -f ${prjTmp}/pr.total_open.${week_start_dt}.${week_end_dt}.still.csv 2>/dev/null

	cat ${prjTmp}/pr.total_open.${week_start_dt}.${week_end_dt}.still.full.csv | while read line
	do
		repo_name=$( echo ${line} | awk -F',' '{print $1}' )
                pr_url=$( echo ${line} | awk -F',' '{print $2}' )
                pull_created_dt=$( echo ${line} | awk -F',' '{print $3}' )
                pull_created_dt_epc=$( date -d "${pull_created_dt}" '+%s' )
                pull_state=$( echo ${line} | awk -F',' '{print $4}' )

		if [[ ${pull_created_dt_epc} -le ${this_week_end_dt_epc} ]]; then
			echo "${repo_name},${pr_url},${pull_created_dt},${pull_state}"  >>${prjTmp}/pr.total_open.${week_start_dt}.${week_end_dt}.still.csv
		fi
	done

	if [[ ! -f ${prjTmp}/pr.total_open.${week_start_dt}.${week_end_dt}.still.csv ]]; then
        	touch ${prjTmp}/pr.total_open.${week_start_dt}.${week_end_dt}.still.csv
	fi

	cat ${prjTmp}/pr.fmt.csv | while read line
	do
        	repo_name=$( echo ${line} | awk -F',' '{print $1}' )
	        pr_url=$( echo ${line} | awk -F',' '{print $2}' )
	        pull_created_dt=$( echo ${line} | awk -F',' '{print $3}' )
	        pull_created_dt_epc=$( date -d "${pull_created_dt}" '+%s' )
	        pull_closed_dt=$( echo ${line} | awk -F',' '{print $4}' )
	        if [[ ${pull_closed_dt} == "null" ]]; then
	                pull_closed_dt="1970-01-01"
	        fi
	        pull_closed_dt_epc=$( date -d "${pull_closed_dt}" '+%s' )
	        pull_state=$( echo ${line} | awk -F',' '{print $5}' )
	
	        if [[ ${pull_created_dt_epc} -ge ${week_start_dt_epc} ]]; then
	                if [[ ${pull_created_dt_epc} -le ${week_end_dt_epc} ]]; then
	                        echo "${repo_name},${pr_url},${pull_created_dt},${pull_state}"  >>${prjTmp}/pr.last_week.${week_start_dt}.${week_end_dt}.new_prs.csv
	                fi
	        fi
	
	        if [[ ${pull_closed_dt_epc} -ge ${week_start_dt_epc} ]]; then
	                if [[ ${pull_closed_dt_epc} -le ${week_end_dt_epc} ]]; then
	                        echo "${repo_name},${pr_url},${pull_closed_dt},${pull_state}"   >>${prjTmp}/pr.last_week.${week_start_dt}.${week_end_dt}.closed_prs.csv
	                fi
	        fi
	
		if [[ ${pull_created_dt_epc} -le ${week_end_dt_epc} ]]; then
			if [[ ${pull_closed_dt_epc} -ge ${week_end_dt_epc} ]]; then
				if [[ ${pull_closed_dt_epc} -le ${this_week_end_dt_epc} ]]; then
					echo "${repo_name},${pr_url},${pull_created_dt},${pull_state}"  >>${prjTmp}/pr.total_open.${week_start_dt}.${week_end_dt}.closed.csv
				else
					echo "${repo_name},${pr_url},${pull_created_dt},${pull_state}"  >>${prjTmp}/pr.total_open.${week_start_dt}.${week_end_dt}.closed.after.csv
				fi
			fi
		fi
	
	done

	cat ${prjTmp}/pr.total_open.${week_start_dt}.${week_end_dt}.still.csv 2>/dev/null 		>${prjTmp}/pr.total_open.${week_start_dt}.${week_end_dt}.csv
	cat ${prjTmp}/pr.total_open.${week_start_dt}.${week_end_dt}.closed.csv 2>/dev/null 		>>${prjTmp}/pr.total_open.${week_start_dt}.${week_end_dt}.csv
        cat ${prjTmp}/pr.total_open.${week_start_dt}.${week_end_dt}.closed.after.csv 2>/dev/null 	>>${prjTmp}/pr.total_open.${week_start_dt}.${week_end_dt}.csv

	if [[ ! -f ${prjTmp}/pr.last_week.${week_start_dt}.${week_end_dt}.new_prs.csv ]]; then
        	touch ${prjTmp}/pr.last_week.${week_start_dt}.${week_end_dt}.new_prs.csv
	fi

	if [[ ! -f ${prjTmp}/pr.last_week.${week_start_dt}.${week_end_dt}.closed_prs.csv ]]; then
        	touch ${prjTmp}/pr.last_week.${week_start_dt}.${week_end_dt}.closed_prs.csv
	fi

	total_prs_open=$( cat ${prjTmp}/pr.total_open.${week_start_dt}.${week_end_dt}.csv | wc -l )
	new_prs_last_week=$( cat ${prjTmp}/pr.last_week.${week_start_dt}.${week_end_dt}.new_prs.csv | wc -l )
	closed_prs_last_week=$( cat ${prjTmp}/pr.last_week.${week_start_dt}.${week_end_dt}.closed_prs.csv | wc -l )

	echo "${week_start_dt},${week_end_dt},${total_prs_open},${new_prs_last_week},${closed_prs_last_week}" >>${prjTmp}/pr.weekly.report.csv
 
        #
        # compute time taken
        calc_timetaken

done

cp -p ${prjTmp}/pr.csv ${prjOut}/pr.raw.csv
cp -p ${prjTmp}/pr.fmt.csv ${prjOut}/pr.raw.fmt.csv
cp -p ${prjTmp}/pr.total_open.*.csv ${prjOut}/
cp -p ${prjTmp}/pr.last_week.*.csv ${prjOut}/
cp -p ${prjTmp}/pr.weekly.report.csv ${prjOut}/pr.weekly.report.csv

# get Top Reviewer
#

cat ${prjOut}/pr.last_week.${this_week_start_dt}.${this_week_end_dt}.closed_prs.csv | while read closed_pr_line
do

    tr_repo=$( echo ${closed_pr_line} | awk -F',' '{print $1}' )
    tr_pr_url=$( echo ${closed_pr_line} | awk -F',' '{print $2}' )
    tr_pr_closed_dt=$( echo ${closed_pr_line} | awk -F',' '{print $3}' )

    if [ $( echo "${tr_pr_url}" | egrep "git.ouryahoo.com" | wc -l ) -eq 1 ]; then
        gitType="github"
    else
        gitType="gitlab"
    fi

    if [ ${gitType} == "github" ]; then
        # ex: https://git.ouryahoo.com/OBI/brr_main/pull/34
        base_api="https://git.ouryahoo.com/api/v3"
        api_token=${github_api_token}
    else
        # ex: https://scm.obieng.com/obi/obi_authorization/merge_requests/1
        base_api="https://scm.obieng.com/api/v4"
        api_token=${gitlab_api_token}
        gitlab_repo_id=$( cat ${prjTmp}/gitlab.repo_repoid.lookup.lst | egrep "^${tr_repo}," | awk -F',' '{print $2}' )

    fi

    repoOwner=$( echo ${tr_pr_url} | awk -F'/' '{print $4}' )
    repoName=$( echo ${tr_pr_url} | awk -F'/' '{print $5}' )
    pr_number=$( echo ${tr_pr_url} | awk -F'/' '{print $7}' )

    if [ ${gitType} == "github" ]; then
        
        github_api_pr_reviews="${base_api}/repos/${repoOwner}/${repoName}/pulls/${pr_number}/reviews"

        curl --head -H 'Content-Type: application/json' -H "Authorization: Bearer ${api_token}" "${github_api_pr_reviews}"      2>/dev/null >${prjTmp}/pr_reviews.head.json
        if [ $( cat ${prjTmp}/pr_reviews.head.json | egrep "HTTP/1.1 200 OK" | wc -l | sed "s/ //g" ) -ne 1 ]; then
            echo "ERROR: Github Curl Failed (github_api_pr_reviews). Exit."
            exit 1
        fi

        reposLastPage=$( cat ${prjTmp}/pr_reviews.head.json| egrep "Link:" | egrep "last" | awk -F"/" '{print $NF}' | awk -F">" '{print $1}' | awk -F"=" '{print $NF}' )
        if [ -z ${reposLastPage} ]; then
            reposLastPage=1
        fi
        i=1
        while [ ${i} -le ${reposLastPage} ]; do
            curl -H 'Content-Type: application/json' -H "Authorization: Bearer ${api_token}" "${github_api_pr_reviews}?page=${i}"   2>/dev/null
            i=$( echo ${i} + 1 | bc )
        done | sed "s/\]\[/,/g"         >${prjTmp}/pr_reviews.json

        for key in $( cat ${prjTmp}/pr_reviews.json | jq '. | keys | .[]' ); do
            cat ${prjTmp}/pr_reviews.json | jq .[${key}]    >${prjTmp}/pr_reviews.key.json
            git_pr_reviewer=$( cat ${prjTmp}/pr_reviews.key.json | jq '.user.login' | sed "s/\"//g" )
            git_pr_review_state=$( cat ${prjTmp}/pr_reviews.key.json | jq '.state' | sed "s/\"//g" )

            echo "${tr_pr_url},${tr_pr_closed_dt},${git_pr_reviewer},${git_pr_review_state}"   >>${prjTmp}/pr_reviews.csv
        done
    else

        gitlab_api_pr_reviews="${base_api}/projects/${gitlab_repo_id}/merge_requests/${pr_number}/approvals?private_token=${api_token}"

        curl --head -H 'Content-Type: application/json' "${gitlab_api_pr_reviews}"      2>/dev/null >${prjTmp}/pr_reviews.head.json
        if [ $( cat ${prjTmp}/pr_reviews.head.json | egrep "HTTP/1.1 200 OK" | wc -l | sed "s/ //g" ) -ne 1 ]; then
            echo "ERROR: Gitlab Curl Failed (gitlab_api_pr_reviews). Exit."
            exit 1
        fi

        reposLastPage=$( cat ${prjTmp}/pr_reviews.head.json | egrep "X-Total-Pages:" | awk -F":" '{print $NF}' | sed "s/ //g" | head -1 )
        reposLastPage=${reposLastPage//[$'\t\r\n ']}
        if [ -z ${reposLastPage} ]; then
            reposLastPage=1
        fi
        i=1
        while [ ${i} -le ${reposLastPage} ]; do
            curl -H 'Content-Type: application/json' "${gitlab_api_pr_reviews}&page=${i}"   2>/dev/null
            i=$( echo ${i} + 1 | bc )
        done | sed "s/\]\[/,/g"         >${prjTmp}/pr_reviews.json

        cat ${prjTmp}/pr_reviews.json | jq '.approved_by[].user.username' | sed "s/\"//g" 2>/dev/null | while read line
        do
            git_pr_reviewer=${line}
            echo "${tr_pr_url},${tr_pr_closed_dt},${git_pr_reviewer},APPROVED"       >>${prjTmp}/pr_reviews.csv
        done
    fi
done

cat ${prjTmp}/pr_reviews.csv | egrep APPROVED | sort -t',' -k3	>${prjTmp}/pr_reviews.sorted.csv

cp -p ${prjTmp}/pr_reviews.csv ${prjOut}/
cp -p ${prjTmp}/pr_reviews.sorted.csv ${prjOut}/

# exclude Managers and non Umesh org 
export exclude_as_TopReviewers="agautham|akaminski|alepekhin|alexlsh|artemciy|atlamax|bangzula|engyash|gattappa|hnguyen|ivan|jaluri|jvaidy|krish34|lyuprapa|mimichen|mstaszewski|nirmala|novyk|pgoyal|pkumar62|psitnikov|rbera|rdodek|rkoven|rjlovato|rmayobre|ssedavnikh|tvanderplas|uchhatr|vlad|wiwit.aditya|all_OBI_repositories"

top_reviewer_weekly_prs=$( cat ${prjTmp}/pr_reviews.sorted.csv | egrep -v "${exclude_as_TopReviewers}" | awk -F',' '{print $3}' | sort | uniq -c | awk '{print $2","$1}' | sort -rn -t',' -k2 | head -1 | awk -F',' '{print $2}' )
top_reviewer_weekly=$( cat ${prjTmp}/pr_reviews.sorted.csv | egrep -v "${exclude_as_TopReviewers}" | awk -F',' '{print $3}' | sort | uniq -c | awk '{print $2","$1}' | sort -rn -t',' -k2 | egrep ",${top_reviewer_weekly_prs}$" | awk -F',' '{print $1}' | tr '\n' ',' | sed "s/,$//g" )

ytd_fields=$(cat /home/ec2-user/pr_reviews.count.rolling_yearly.csv | awk -F',' '{print NF}' | sort -nr -u)
top_reviewer_ytd=$( cat /home/ec2-user/pr_reviews.count.rolling_yearly.csv | egrep -v "${exclude_as_TopReviewers}" | sort -nr -t',' -k${ytd_fields} | awk -F':' '{print $1}' | head -1 )
top_reviewer_ytd_prs=$( cat /home/ec2-user/pr_reviews.count.rolling_yearly.csv | egrep -v "${exclude_as_TopReviewers}" | sort -nr -t',' -k${ytd_fields} | awk -F',' '{print $NF}' | head -1 )

mtd_fields=$(cat /home/ec2-user/pr_reviews.count.rolling_monthly.csv | awk -F',' '{print NF}' | sort -nr -u)
top_reviewer_mtd=$( cat /home/ec2-user/pr_reviews.count.rolling_monthly.csv | egrep -v "${exclude_as_TopReviewers}" | sort -nr -t',' -k${mtd_fields} | awk -F':' '{print $1}' | head -1 )
top_reviewer_mtd_prs=$( cat /home/ec2-user/pr_reviews.count.rolling_monthly.csv | egrep -v "${exclude_as_TopReviewers}" | sort -nr -t',' -k${mtd_fields} | awk -F',' '{print $NF}' | head -1 )


# create HTML report
#
echo "
<html>
<h3>OBI - Weekly Pull Requests Report : ${this_week_end_dt}</h3>
<body>
<table id="myTable" border="1">
<thead>
<tr>
<th bgcolor="lightblue">Metrics</th>
<th bgcolor="lightblue">Top Reviewer</th>
<th bgcolor="lightblue">PRs</th>
</tr>
</thead>
<tbody>
<tr>
<td>Weekly</td>
<td>${top_reviewer_weekly}</td>
<td>${top_reviewer_weekly_prs}</td>
</tr>
<tr>
<td>MTD</td>
<td>${top_reviewer_mtd}</td>
<td>${top_reviewer_mtd_prs}</td>
</tr>
<tr>
<td>YTD</td>
<td>${top_reviewer_ytd}</td>
<td>${top_reviewer_ytd_prs}</td>
</tr>
</tbody>
</table>
<br>
<table id="myTable" border="1">
<thead>
<tr>
<th bgcolor="lightblue">Week Start Date</th>
<th bgcolor="lightblue">Week End Date</th>
<th bgcolor="lightblue">Total PRs Open</th>
<th bgcolor="lightblue">New PRs</th>
<th bgcolor="lightblue">Closed PRs</th>
</tr>
</thead>
<tbody>
">${prjOut}/pr.weekly.report.html

cat ${prjOut}/pr.weekly.report.csv | while read line
do
	week_start_dt=$( echo ${line} | awk -F',' '{print $1}' )
	week_end_dt=$( echo ${line} | awk -F',' '{print $2}' )
	total_prs_open=$( echo ${line} | awk -F',' '{print $3}' )
	new_prs_last_week=$( echo ${line} | awk -F',' '{print $4}' )
	closed_prs_last_week=$( echo ${line} | awk -F',' '{print $5}' )

echo "
<tr>
<td>${week_start_dt}</td>
<td>${week_end_dt}</td>
<td>${total_prs_open}</td>
<td>${new_prs_last_week}</td>
<td>${closed_prs_last_week}</td>
</tr>
">>${prjOut}/pr.weekly.report.html

done

echo "
</tbody>
</table>
<br><br>
<h3>Reviewers Last Week [ ${this_week_start_dt} - ${this_week_end_dt} ]</h4>
<body>
<table id="myTable" border="1">
<thead>
<tr>
<th bgcolor="lightblue">Closed Pull Requests</th>
<th bgcolor="lightblue">Closed Date</th>
<th bgcolor="lightblue">Reviewer</th>
</tr>
</thead>
<tbody>
">>${prjOut}/pr.weekly.report.html

cat ${prjOut}/pr_reviews.sorted.csv | while read line
do
        pr_closed_url=$( echo ${line} | awk -F',' '{print $1}' )
        pr_closed_dt=$( echo ${line} | awk -F',' '{print $2}' )
        pr_reviewer=$( echo ${line} | awk -F',' '{print $3}' )

echo "
<tr>
<td>${pr_closed_url}</td>
<td>${pr_closed_dt}</td>
<td>${pr_reviewer}</td>
</tr>
">>${prjOut}/pr.weekly.report.html

done

echo "
</tbody>
</table>
<br>
<table id="myTable" border="1">
<thead>
<tr>
<th bgcolor="lightblue">Reviewer</th>
<th bgcolor="lightblue">Number of PRs Reviewed</th>
</tr>
</thead>
<tbody>
">>${prjOut}/pr.weekly.report.html

cat ${prjOut}/pr_reviews.sorted.csv | awk -F',' '{print $3}' | sort | uniq -c | awk '{print $2","$1}' | sort -rn -t',' -k2 | while read line
do
        pr_reviewer=$( echo ${line} | awk -F',' '{print $1}' )
        num_prs_reviewed=$( echo ${line} | awk -F',' '{print $2}' )

echo "
<tr>
<td>${pr_reviewer}</td>
<td>${num_prs_reviewed}</td>
</tr>
">>${prjOut}/pr.weekly.report.html

done

echo "
</tbody>
</table>
<br><br>
<h4>New PRs Last Week [ ${this_week_start_dt} - ${this_week_end_dt} ]</h4>
<body>
<table id="myTable" border="1">
<thead>
<tr>
<th bgcolor="lightblue">Sl No</th>
<th bgcolor="lightblue">Repository</th>
<th bgcolor="lightblue">Pull Request URL</th>
<th bgcolor="lightblue">Created Date</th>
<th bgcolor="lightblue">Status</th>
</tr>
</thead>
<tbody>
">>${prjOut}/pr.weekly.report.html

new_sl=0
cat ${prjOut}/pr.last_week.${this_week_start_dt}.${this_week_end_dt}.new_prs.csv | while read line
do
	new_sl=$( echo $new_sl + 1 | bc )
        repo_name=$( echo ${line} | awk -F',' '{print $1}' )
        pr_url=$( echo ${line} | awk -F',' '{print $2}' )
        created_dt=$( echo ${line} | awk -F',' '{print $3}' )
        status=$( echo ${line} | awk -F',' '{print $4}' )

echo "
<tr>
<td>${new_sl}</td>
<td>${repo_name}</td>
<td>${pr_url}</td>
<td>${created_dt}</td>
<td>${status}</td>
</tr>
">>${prjOut}/pr.weekly.report.html

done

echo "
</tbody>
</table>
<br><br>
<h4>Closed PRs Last Week [ ${this_week_start_dt} - ${this_week_end_dt} ]</h4>
<body>
<table id="myTable" border="1">
<thead>
<tr>
<th bgcolor="lightblue">Sl No</th>
<th bgcolor="lightblue">Repository</th>
<th bgcolor="lightblue">Pull Request URL</th>
<th bgcolor="lightblue">Closed Date</th>
<th bgcolor="lightblue">Status</th>
</tr>
</thead>
<tbody>
">>${prjOut}/pr.weekly.report.html

closed_sl=0
cat ${prjOut}/pr.last_week.${this_week_start_dt}.${this_week_end_dt}.closed_prs.csv | while read line
do
        closed_sl=$( echo $closed_sl + 1 | bc )
        repo_name=$( echo ${line} | awk -F',' '{print $1}' )
        pr_url=$( echo ${line} | awk -F',' '{print $2}' )
        closed_dt=$( echo ${line} | awk -F',' '{print $3}' )
        status=$( echo ${line} | awk -F',' '{print $4}' )

echo "
<tr>
<td>${closed_sl}</td>
<td>${repo_name}</td>
<td>${pr_url}</td>
<td>${closed_dt}</td>
<td>${status}</td>
</tr>
">>${prjOut}/pr.weekly.report.html

done

echo "
</tbody>
</table>
<br><br>
<h4>Total PRs Open [ ${this_week_start_dt} - ${this_week_end_dt} ]</h4>
<body>
<table id="myTable" border="1">
<thead>
<tr>
<th bgcolor="lightblue">Sl No</th>
<th bgcolor="lightblue">Repository</th>
<th bgcolor="lightblue">Pull Request URL</th>
<th bgcolor="lightblue">Created Date</th>
<th bgcolor="lightblue">Status</th>
</tr>
</thead>
<tbody>
">>${prjOut}/pr.weekly.report.html

total_open_sl=0
cat ${prjOut}/pr.total_open.${this_week_start_dt}.${this_week_end_dt}.csv | while read line
do
        total_open_sl=$( echo $total_open_sl + 1 | bc )
        repo_name=$( echo ${line} | awk -F',' '{print $1}' )
        pr_url=$( echo ${line} | awk -F',' '{print $2}' )
        created_dt=$( echo ${line} | awk -F',' '{print $3}' )
        status=$( echo ${line} | awk -F',' '{print $4}' )

echo "
<tr>
<td>${total_open_sl}</td>
<td>${repo_name}</td>
<td>${pr_url}</td>
<td>${created_dt}</td>
<td>${status}</td>
</tr>
">>${prjOut}/pr.weekly.report.html

done

echo "
</tbody>
</table>
</body>
</html>">>${prjOut}/pr.weekly.report.html

#
# compute time taken
calc_timetaken

