#!/usr/bin/sh


set +x

# Initialize variables
#
prjHome=$(pwd)
prjTmp="${prjHome}/tmp"
prjOut="${prjHome}/output"
cts=$( date '+%Y%m%d_%H%M%S' )
repoOwner=OBI
github_base_api="https://git.ouryahoo.com/api/v3"
## gitlab_base_api="https://scm.obieng.com/api/v4"
# Below variables are stored as secret text(s) and are defined in the Jenkins Build Environment
#github_api_token=""
#gitlab_api_token=""
# Common Target directory
targetDir="/var/lib/jenkins/git_reports"


# Cleanup previous run
#
rm -rf ${prjTmp} ${prjOut} 2>/dev/null
mkdir -p ${prjTmp} ${prjOut} 
mkdir -p ${targetDir}
ls -l ${targetDir}/*csv 2>/dev/null
wc -l ${targetDir}/*csv 2>/dev/null
if [ ! -f ${targetDir}/pr.full.csv ]; then
	touch ${targetDir}/pr.full.csv
fi

# calculate the time taken in seconds
calc_timetaken() {
        if [[ $epmystarttime == "" ]]; then
                epmystarttime=$( date +%s )
        fi
        epmyendtime=$( date +%s )
        eptimediff=$( expr $epmyendtime - $epmystarttime )
        epmystarttime=$( echo -e $epmyendtime )

		echo "timetaken $eptimediff secs"
}
calc_timetaken	>/dev/null

# Read active repositories and loop through each repo to get pull request (PR) details
#

sl_no=1
max_sl_no=$( cat ${targetDir}/repos.active | wc -l )

#library_BE
cat ${targetDir}/repos.active | while read repoLine
do
    #gitType,repoName
	gitType=$( echo ${repoLine} | awk -F',' '{print $1}' )
	repoName=$( echo ${repoLine} | awk -F',' '{print $2}' | awk -F'#' '{print $1}' )
	echo ""
    echo ""
    echo ""
	echo "INFO: ${sl_no} / ${max_sl_no} - ${gitType} : ${repoName} : Start reading PRs"

    if [[ ${gitType} == "github" ]]; then
        base_api="https://git.ouryahoo.com/api/v3"
        api_token=${github_api_token}
##     else
##         base_api="https://scm.obieng.com/api/v4"
##         api_token=${gitlab_api_token}
##         gitlab_repo_id=$( echo "${repoLine}" | awk -F',' '{print $2}' | awk -F'#' '{print $NF}' )
## 		echo "${repoName},${gitlab_repo_id}" >>${prjTmp}/gitlab.repo_repoid.lookup.lst
    fi
    
    if [[ ${gitType} == "github" ]]; then
		github_api_pr_all="${base_api}/repos/${repoOwner}/${repoName}/pulls?state=all&per_page=100"

		curl --head -H 'Content-Type: application/json' -H "Authorization: Bearer ${api_token}" "${github_api_pr_all}"	2>/dev/null >${prjTmp}/pr.head.json
		if [[ $( cat ${prjTmp}/pr.head.json | egrep "HTTP/1.1 200 OK" | wc -l | sed "s/ //g" ) -ne 1 ]]; then
			echo "ERROR: Github Curl Failed (github_api_pulls). Exit."
    		exit 1
		fi

		reposLastPage=$( cat ${prjTmp}/pr.head.json| egrep "Link:" | egrep "last" | awk -F"/" '{print $NF}' | awk -F">" '{print $1}' | awk -F"=" '{print $NF}' )
		if [[ -z ${reposLastPage} ]]; then
    		reposLastPage=1
        fi

		rm -f ${prjTmp}/pr.${repoName}.json
		i=1
        while [[ ${i} -le ${reposLastPage} ]]; do
			p_out=$( curl -H 'Content-Type: application/json' -H "Authorization: Bearer ${api_token}" "${github_api_pr_all}&page=${i}"	2>/dev/null )
            echo -n ${p_out}
			i=$( echo ${i} + 1 | bc )
		done | sed "s/\]\[/,/g"  >>${prjTmp}/pr.${repoName}.json

       	for key in $( cat ${prjTmp}/pr.${repoName}.json | jq '. | keys | .[]' ); do
       		cat ${prjTmp}/pr.${repoName}.json | jq .[${key}]	>${prjTmp}/pr.key.json

       		git_pr_url=$( cat ${prjTmp}/pr.key.json | jq '.html_url' | sed "s/\"//g" )
			# calculating md5sum so that for searching it would be faster for the url string
			git_pr_url_md5sum=$( echo ${git_pr_url} | md5sum | awk '{print $1}' )
            #logic to skip for closed prs which were already read
            if [[ $( cat ${targetDir}/pr.full.csv | egrep ",${git_pr_url_md5sum}," | egrep "closed" | wc -l ) -ne 0 ]]; then
            	cat ${targetDir}/pr.full.csv | egrep ",${git_pr_url_md5sum}," | egrep ",closed," >>${prjTmp}/pr.csv
                echo "SKIP: ${git_pr_url} - closed"
             	continue
            fi
            # get pr title
            git_pr_title=$( cat ${prjTmp}/pr.key.json | jq '.title' | sed "s/\"//g" | sed "s/,//g" )
       		# states can be closed or open
			git_pr_state=$( cat ${prjTmp}/pr.key.json | jq '.state' | sed "s/\"//g" )


			echo "INFO: ${git_pr_url} - ${git_pr_state}"

			git_pr_creator=$( cat ${prjTmp}/pr.key.json | jq '.user.login' | sed "s/\"//g" )
       		git_pr_created_at=$( cat ${prjTmp}/pr.key.json | jq '.created_at' | sed "s/\"//g" | sed "s/T/ /g" | sed "s/Z//g" | awk -F'.' '{print $1}' )
       		git_pr_created_at_yyyy=$( echo "${git_pr_created_at}" | awk -F'-' '{print $1}' )
            git_pr_created_at_yyyymm=$( echo "${git_pr_created_at}" | awk -F'-' '{print $1$2}' )
            # for open PR we will either have null or updated_at
			git_pr_closed_at=$( cat ${prjTmp}/pr.key.json | jq '.closed_at' | sed "s/\"//g" | sed "s/T/ /g" | sed "s/Z//g" | awk -F'.' '{print $1}' )
			if [[ ${git_pr_closed_at} == "null" ]]; then
        		git_pr_closed_at=$( cat ${prjTmp}/pr.key.json | jq '.updated_at' | sed "s/\"//g" | sed "s/T/ /g" | sed "s/Z//g" | awk -F'.' '{print $1}' )
			fi
			git_pr_last_updated_at=${git_pr_closed_at}
            git_pr_last_updated_at_yyyy=$( echo "${git_pr_last_updated_at}" | awk -F'-' '{print $1}' )
            git_pr_last_updated_at_yyyymm=$( echo "${git_pr_last_updated_at}" | awk -F'-' '{print $1$2}' )
			
       		# need pr number for PR review api call
			git_pr_number=$( cat ${prjTmp}/pr.key.json | jq '.number' | sed "s/\"//g" )
			github_api_pr_reviews="${base_api}/repos/${repoOwner}/${repoName}/pulls/${git_pr_number}/reviews"
			
			curl --head -H 'Content-Type: application/json' -H "Authorization: Bearer ${api_token}" "${github_api_pr_reviews}"	2>/dev/null >${prjTmp}/pr_reviews.head.json
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
				p_out=$( curl -H 'Content-Type: application/json' -H "Authorization: Bearer ${api_token}" "${github_api_pr_reviews}?page=${i}"	2>/dev/null )
            	echo -n ${p_out}
				i=$( echo ${i} + 1 | bc )
			done | sed "s/\]\[/,/g" 	>${prjTmp}/pr_reviews.json

			for key in $( cat ${prjTmp}/pr_reviews.json | jq '. | keys | .[]' ); do
                cat ${prjTmp}/pr_reviews.json | jq .[${key}]	>${prjTmp}/pr_reviews.key.json
				
				git_pr_reviewer=$( cat ${prjTmp}/pr_reviews.key.json | jq '.user.login' | sed "s/\"//g" )
        		git_pr_review_state=$( cat ${prjTmp}/pr_reviews.key.json | jq '.state' | sed "s/\"//g" )

				echo "${git_pr_reviewer},${git_pr_review_state}"
			done | egrep "APPROVED" >${prjTmp}/pr_reviews.reviewers

			if [[ ! -s ${prjTmp}/pr_reviews.reviewers ]]; then
				echo "NA,NA" >${prjTmp}/pr_reviews.reviewers
			fi

			cat ${prjTmp}/pr_reviews.reviewers | while read git_pr_reviewer_info
			do
				git_pr_reviewer=$( echo ${git_pr_reviewer_info} | awk -F',' '{print $1}' )
				git_pr_review_state=$( echo ${git_pr_reviewer_info} | awk -F',' '{print $2}' )

				echo "${gitType},${repoName},${git_pr_url_md5sum},${git_pr_url},${git_pr_title},${git_pr_state},${git_pr_creator},${git_pr_created_at},${git_pr_created_at_yyyy},${git_pr_created_at_yyyymm},${git_pr_last_updated_at},${git_pr_last_updated_at_yyyy},${git_pr_last_updated_at_yyyymm},${git_pr_reviewer},${git_pr_review_state}"	>>${prjTmp}/pr.csv
			done
       	done
    fi
    
##     if [[ ${gitType} == "gitlab" ]]; then
## 		gitlab_api_pr_all="${base_api}/projects/${gitlab_repo_id}/merge_requests?state=all&private_token=${api_token}&per_page=100"
##         
##         curl --head -H 'Content-Type: application/json' "${gitlab_api_pr_all}"	2>/dev/null >${prjTmp}/pr.head.json
## 		if [[ $( cat ${prjTmp}/pr.head.json | egrep "HTTP/1.1 200 OK" | wc -l | sed "s/ //g" ) -ne 1 ]]; then
## 			echo "ERROR: Gitlab Curl Failed (gitlab_api_pulls). Exit."
##     		exit 1
## 		fi
## 
## 		reposLastPage=$( cat ${prjTmp}/pr.head.json | egrep "X-Total-Pages:" | awk -F":" '{print $NF}' | sed "s/ //g" | head -1 )
## 		reposLastPage=${reposLastPage//[$'\t\r\n ']}
## 		if [[ -z ${reposLastPage} ]]; then
##     		reposLastPage=1
## 		fi
## 		
## 		rm -f ${prjTmp}/pr.${repoName}.json
## 		i=1
## 		while [[ ${i} -le ${reposLastPage} ]]; do
## 			p_out=$( curl -H 'Content-Type: application/json' "${gitlab_api_pr_all}&page=${i}"	2>/dev/null )
## 			echo -n ${p_out}
## 			i=$( echo ${i} + 1 | bc )
## 		done | sed "s/\]\[/,/g" 	>>${prjTmp}/pr.${repoName}.json
##         
##        	for key in $( cat ${prjTmp}/pr.${repoName}.json | jq '. | keys | .[]' ); do
##        		cat ${prjTmp}/pr.${repoName}.json | jq .[${key}]	>${prjTmp}/pr.key.json
##        	
##            	git_pr_url=$( cat ${prjTmp}/pr.key.json | jq '.web_url' | sed "s/\"//g" )
## 			# calculating md5sum so that for searching it would be faster for the url string
## 			git_pr_url_md5sum=$( echo ${git_pr_url} | md5sum | awk '{print $1}' )
##             if [[ $( cat ${targetDir}/pr.full.csv | egrep ",${git_pr_url_md5sum}," | egrep "closed" | wc -l ) -ne 0 ]]; then
##             	cat ${targetDir}/pr.full.csv | egrep ",${git_pr_url_md5sum}," | egrep ",closed,|,ignoreclosed," >>${prjTmp}/pr.csv
##                 echo "SKIP: ${git_pr_url} - closed"
##              	continue
##             fi
##             # get pr title
##             git_pr_title=$( cat ${prjTmp}/pr.key.json | jq '.title' | sed "s/\"//g" | sed "s/,//g" )
##         	# states can be closed, merged or opened
## 			git_pr_state=$( cat ${prjTmp}/pr.key.json | jq '.state' | sed "s/\"//g" )
## 
## 
## 			echo "INFO: ${git_pr_url} - ${git_pr_state}"
## 
## 			git_pr_creator=$( cat ${prjTmp}/pr.key.json | jq '.author.username' | sed "s/\"//g" )
## 			git_pr_created_at=$( cat ${prjTmp}/pr.key.json | jq '.created_at' | sed "s/\"//g" | sed "s/T/ /g" | sed "s/Z//g" | awk -F'.' '{print $1}' )
##         	git_pr_created_at_yyyy=$( echo "${git_pr_created_at}" | awk -F'-' '{print $1}' )
##             git_pr_created_at_yyyymm=$( echo "${git_pr_created_at}" | awk -F'-' '{print $1$2}' )
##             # for open PR we will either have null or updated_at
## 			git_pr_closed_at=$( cat ${prjTmp}/pr.key.json | jq '.closed_at' | sed "s/\"//g" | sed "s/T/ /g" | sed "s/Z//g" | awk -F'.' '{print $1}' )
##         	if [[ ${git_pr_state} == "merged" ]]; then
##         		git_pr_closed_at=$( cat ${prjTmp}/pr.key.json | jq '.merged_at' | sed "s/\"//g" | sed "s/T/ /g" | sed "s/Z//g" | awk -F'.' '{print $1}' )
## 			fi
## 			if [[ ${git_pr_closed_at} == "null" ]]; then
##         		git_pr_closed_at=$( cat ${prjTmp}/pr.key.json | jq '.updated_at' | sed "s/\"//g" | sed "s/T/ /g" | sed "s/Z//g" | awk -F'.' '{print $1}' )
## 			fi
## 			git_pr_last_updated_at=${git_pr_closed_at}
##             git_pr_last_updated_at_yyyy=$( echo "${git_pr_last_updated_at}" | awk -F'-' '{print $1}' )
##             git_pr_last_updated_at_yyyymm=$( echo "${git_pr_last_updated_at}" | awk -F'-' '{print $1$2}' )
## 			
## 			# to comply with github, merged status is considered as closed
##       if [[ ${git_pr_state} == "closed" ]]; then
##         git_pr_state="ignoreclosed"
##       fi
## 			if [[ ${git_pr_state} == "merged" ]]; then
## 				git_pr_state="closed"
## 			fi
## 			# to comply with github, opened status is renamed as open
## 			if [[ ${git_pr_state} == "opened" ]]; then
## 				git_pr_state="open"
## 			fi
## 
## 			# need pr number for PR review api call
## 			pr_number=$( cat ${prjTmp}/pr.key.json | jq '.iid' | sed "s/\"//g" )
## 			gitlab_api_pr_reviews="${base_api}/projects/${gitlab_repo_id}/merge_requests/${pr_number}/approvals?private_token=${api_token}"
## 			
## 			curl --head -H 'Content-Type: application/json' "${gitlab_api_pr_reviews}"	2>/dev/null >${prjTmp}/pr_reviews.head.json
## 			if [ $( cat ${prjTmp}/pr_reviews.head.json | egrep "HTTP/1.1 200 OK" | wc -l | sed "s/ //g" ) -ne 1 ]; then
## 				echo "ERROR: Gitlab Curl Failed (gitlab_api_pr_reviews). Exit."
##     			exit 1
## 			fi
## 	
## 			reposLastPage=$( cat ${prjTmp}/pr_reviews.head.json | egrep "X-Total-Pages:" | awk -F":" '{print $NF}' | sed "s/ //g" | head -1 )
## 			reposLastPage=${reposLastPage//[$'\t\r\n ']}
##             if [ -z ${reposLastPage} ]; then
##     			reposLastPage=1
## 			fi
## 			i=1
## 			while [ ${i} -le ${reposLastPage} ]; do
## 				p_out=$( curl -H 'Content-Type: application/json' "${gitlab_api_pr_reviews}&page=${i}"	2>/dev/null )
##             	echo -n ${p_out}
## 				i=$( echo ${i} + 1 | bc )
## 			done | sed "s/\]\[/,/g" 	>${prjTmp}/pr_reviews.json
## 
## 			cat ${prjTmp}/pr_reviews.json | jq '.approved_by[].user.username' | sed "s/\"//g" 2>/dev/null | while read line
##             do
##             	echo "${line}"
## 			done >${prjTmp}/pr_reviews.reviewers
## 
## 			if [[ ! -s ${prjTmp}/pr_reviews.reviewers ]]; then
## 				echo "NA" >${prjTmp}/pr_reviews.reviewers
## 				git_pr_review_state="NA"
## 			else
## 				git_pr_review_state="APPROVED"
## 			fi
## 
## 			cat ${prjTmp}/pr_reviews.reviewers | while read git_pr_reviewer
## 			do
## 				echo "${gitType},${repoName},${git_pr_url_md5sum},${git_pr_url},${git_pr_title},${git_pr_state},${git_pr_creator},${git_pr_created_at},${git_pr_created_at_yyyy},${git_pr_created_at_yyyymm},${git_pr_last_updated_at},${git_pr_last_updated_at_yyyy},${git_pr_last_updated_at_yyyymm},${git_pr_reviewer},${git_pr_review_state}"	>>${prjTmp}/pr.csv
## 			done
##         done
##     fi

	num_prs_maxkey=$( cat ${prjTmp}/pr.${repoName}.json | jq '. | keys | .[]' | tail -1 )
    if [[ -z ${num_prs_maxkey} ]]; then
        num_prs=0
    else
        num_prs=$( echo ${num_prs_maxkey} + 1 | bc )
    fi

    echo "INFO: ${sl_no} / ${max_sl_no} - ${gitType} : ${repoName} : End reading ${num_prs} PRs : $( calc_timetaken )"
    sl_no=$( echo ${sl_no} + 1 | bc )
done

cat ${prjTmp}/pr.csv | sort -u >${prjOut}/pr.csv
cp ${targetDir}/pr.full.csv ${targetDir}/pr.full.${cts}.csv
cp ${prjOut}/pr.csv ${targetDir}/pr.full.csv

