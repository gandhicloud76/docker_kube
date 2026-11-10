#!/usr/bin/sh

## __author__ = 'Anil Reddy Dalli'
##
## Get Pull Request Reviewers from Gitlab and Github (for OBI team)
## 
## Scan through all active repositories of Github and Gitlab for all Pull Requests to generate report on reviewers

prjHome=$(pwd)
prjTmp="${prjHome}/tmp"
prjOut="${prjHome}/output"
repoOwner=OBI

rm -rf ${prjTmp} ${prjOut} 2>/dev/null
mkdir -p ${prjTmp} ${prjOut}

pr_cutoff_date_epc=$( date -d "2021-01-01T00:00:00Z" '+%s' )

github_base_api="https://git.ouryahoo.com/api/v3"
gitlab_base_api="https://scm.obieng.com/api/v4"

# Below variables are staored as secret text(s) and are used in the Jenkins Build Environment
#github_api_token=""
#gitlab_api_token=""

# get Gitlab active repositories (i.e. archived=false)
#
gitlab_api_repos="${gitlab_base_api}/projects?private_token=${gitlab_api_token}&per_page=100"

curl --head -H 'Content-Type: application/json' "${gitlab_api_repos}"	2>/dev/null >${prjTmp}/repos.head.json
if [ $( cat ${prjTmp}/repos.head.json | egrep "HTTP/1.1 200 OK" | wc -l | sed "s/ //g" ) -ne 1 ]; then
	echo "ERROR: Gitlab Curl Failed (gitlab_api_repos). Exit."
    exit 1
fi

reposLastPage=$( cat ${prjTmp}/repos.head.json | egrep "X-Total-Pages:" | awk -F":" '{print $NF}' | sed "s/ //g" | head -1 )
reposLastPage=${reposLastPage//[$'\t\r\n ']}
if [ -z ${reposLastPage} ]; then
    reposLastPage=1
fi
i=1
while [ ${i} -le ${reposLastPage} ]; do
	curl -H 'Content-Type: application/json' "${gitlab_api_repos}&page=${i}"	2>/dev/null
	i=$( echo ${i} + 1 | bc )
done | sed "s/\]\[/,/g" 	>${prjTmp}/repos.json

repoNamesAll_array=($( cat ${prjTmp}/repos.json | jq '.[].path_with_namespace' | sed "s/\"//g" | sed "s/ //g" | egrep -v "AlexanderLepekhin|PuneetSharma" | sort -d | tr '\n' ' ' ))
repoNamesActive_array=($( cat ${prjTmp}/repos.json | jq '.[] | select( "\(.archived)" == "false" ) | "\(.path_with_namespace)#\(.id)"' | sed "s/\"//g" | sed "s/ //g" | egrep -v "AlexanderLepekhin|PuneetSharma" | sort -d | tr '\n' ' ' ))    

for repoFullNameId in ${repoNamesActive_array[@]}; do
    repoNameId=$( echo "${repoFullNameId}" | awk -F'/' '{print $NF}' )
    repoNamesActive_array_gl+=(${repoNameId})
done
echo "#########################################################################"
echo "### Gitlab : active repos ${#repoNamesActive_array[@]} (total ${#repoNamesAll_array[@]})"

# get Github active repositories (i.e. archived=false)
#
github_api_repos="${github_base_api}/orgs/${repoOwner}/repos"

curl --head -H 'Content-Type: application/json' -H "Authorization: Bearer ${github_api_token}" "${github_api_repos}"	2>/dev/null >${prjTmp}/repos.head.json
if [ $( cat ${prjTmp}/repos.head.json | egrep "HTTP/1.1 200 OK" | wc -l | sed "s/ //g" ) -ne 1 ]; then
	echo "ERROR: Github Curl Failed (github_api_repos). Exit."
    exit 1
fi
	
reposLastPage=$( cat ${prjTmp}/repos.head.json | egrep "Link:" | egrep "last" | awk -F"/" '{print $NF}' | awk -F">" '{print $1}' | awk -F"=" '{print $NF}' )
if [ -z ${reposLastPage} ]; then
    reposLastPage=1
fi
i=1
while [ ${i} -le ${reposLastPage} ]; do
	curl -H 'Content-Type: application/json' -H "Authorization: Bearer ${github_api_token}" "${github_api_repos}?page=${i}"	2>/dev/null
	i=$( echo ${i} + 1 | bc )
done | sed "s/\]\[/,/g" 	>${prjTmp}/repos.json
	
repoNamesAll_array=($( cat ${prjTmp}/repos.json | jq '.[].full_name' | sed "s/\"//g" | sort -d | tr '\n' ' ' ))
repoNamesActive_array=($( cat ${prjTmp}/repos.json | jq '.[] | select( "\(.archived)" == "false" ) | "\(.full_name)"' | sed "s/\"//g" | sort -d | tr '\n' ' ' ))
	
for repoFullName in ${repoNamesActive_array[@]}; do
    repoName=$( echo "${repoFullName}" | awk -F"/" '{print $NF}' )
    repoNamesActive_array_gh+=(${repoName})
done
echo "### Github : active repos ${#repoNamesActive_array[@]} (total ${#repoNamesAll_array[@]})"

# create list of project repositories to scan all PRs
#
for repoName in ${repoNamesActive_array_gl[@]}; do
    repoNamesActive_array_gl_map+=(${repoName}":gitlab")
done
for repoName in ${repoNamesActive_array_gh[@]}; do
    repoNamesActive_array_gh_map+=(${repoName}":github")
done
project_repos_map_array=("${repoNamesActive_array_gl_map[@]}" "${repoNamesActive_array_gh_map[@]}")
echo "### Gitlab+Github : ${#project_repos_map_array[@]} repos to be scanned for all PRs"
echo "#########################################################################"
#project_repos_map_array=(obi_esb#202:gitlab obi_tools#66:gitlab obi_database:github obi_scs:github)

# loop through project repositories and scan all PRs
#
repo_cnt=1
for repoNameGitType in ${project_repos_map_array[@]}; do
    repoName=$( echo "${repoNameGitType}" | awk -F':' '{print $1}' | awk -F'#' '{print $1}' )
    gitType=$( echo "${repoNameGitType}" | awk -F':' '{print $2}' )

    if [ ${gitType} == "github" ]; then
        base_api="https://git.ouryahoo.com/api/v3"
        api_token=${github_api_token}
    else
        base_api="https://scm.obieng.com/api/v4"
        api_token=${gitlab_api_token}
        gitlab_repo_id=$( echo "${repoNameGitType}" | awk -F':' '{print $1}' | awk -F'#' '{print $NF}' )
    fi

    echo "[${repo_cnt}/${#project_repos_map_array[@]}] - $(date '+%Y-%m-%d %H:%m')"
	echo "${gitType} : ${base_api} : ${repoName}"
    
    if [ ${gitType} == "github" ]; then
		github_api_pulls="${base_api}/repos/${repoOwner}/${repoName}/pulls?state=all"
		
		curl --head -H 'Content-Type: application/json' -H "Authorization: Bearer ${api_token}" "${github_api_pulls}"	2>/dev/null >${prjTmp}/pulls.head.json
		if [ $( cat ${prjTmp}/pulls.head.json | egrep "HTTP/1.1 200 OK" | wc -l | sed "s/ //g" ) -ne 1 ]; then
			echo "ERROR: Github Curl Failed (github_api_pulls). Exit."
    		exit 1
		fi
	
		reposLastPage=$( cat ${prjTmp}/pulls.head.json| egrep "Link:" | egrep "last" | awk -F"/" '{print $NF}' | awk -F">" '{print $1}' | awk -F"=" '{print $NF}' )
		if [ -z ${reposLastPage} ]; then
    		reposLastPage=1
		fi
		i=1
		while [ ${i} -le ${reposLastPage} ]; do
			curl -H 'Content-Type: application/json' -H "Authorization: Bearer ${api_token}" "${github_api_pulls}&page=${i}" 2>/dev/null | tr -d '\n'
			i=$( echo ${i} + 1 | bc )
		done | sed "s/\]\[/,/g" >${prjTmp}/pulls.${repoName}.json
         	
        for key in $( cat ${prjTmp}/pulls.${repoName}.json | jq '. | keys | .[]' ); do
        	cat ${prjTmp}/pulls.${repoName}.json | jq .[${key}]	>${prjTmp}/pulls.key.json
        	
			pr_number=$( cat ${prjTmp}/pulls.key.json | jq '.number' | sed "s/\"//g" )
			git_pr_url=$( cat ${prjTmp}/pulls.key.json | jq '.html_url' | sed "s/\"//g" )
			git_pr_created_at=$( cat ${prjTmp}/pulls.key.json | jq '.created_at' | sed "s/\"//g" )
            git_pr_creator=$( cat ${prjTmp}/pulls.key.json | jq '.user.login' | sed "s/\"//g" )

			github_api_pr_reviews="${base_api}/repos/${repoOwner}/${repoName}/pulls/${pr_number}/reviews"
			
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
				curl -H 'Content-Type: application/json' -H "Authorization: Bearer ${api_token}" "${github_api_pr_reviews}?page=${i}"	2>/dev/null
				i=$( echo ${i} + 1 | bc )
			done | sed "s/\]\[/,/g" 	>${prjTmp}/pr_reviews.json

			for key in $( cat ${prjTmp}/pr_reviews.json | jq '. | keys | .[]' ); do
                cat ${prjTmp}/pr_reviews.json | jq .[${key}]	>${prjTmp}/pr_reviews.key.json
				
				git_pr_reviewer=$( cat ${prjTmp}/pr_reviews.key.json | jq '.user.login' | sed "s/\"//g" )
        		git_pr_review_state=$( cat ${prjTmp}/pr_reviews.key.json | jq '.state' | sed "s/\"//g" )

				echo "${git_pr_reviewer},${git_pr_review_state},${git_pr_url},${git_pr_created_at},${git_pr_creator}"	>>${prjTmp}/pr_reviews.csv
			done
        	
        done
    fi

    if [ ${gitType} == "gitlab" ]; then
		gitlab_api_pulls="${base_api}/projects/${gitlab_repo_id}/merge_requests?state=all&private_token=${api_token}&per_page=100"
        
		curl --head -H 'Content-Type: application/json' "${gitlab_api_pulls}"	2>/dev/null >${prjTmp}/pulls.head.json
		if [ $( cat ${prjTmp}/pulls.head.json | egrep "HTTP/1.1 200 OK" | wc -l | sed "s/ //g" ) -ne 1 ]; then
			echo "ERROR: Gitlab Curl Failed (gitlab_api_pulls). Exit."
    		exit 1
		fi
	
		reposLastPage=$( cat ${prjTmp}/pulls.head.json | egrep "X-Total-Pages:" | awk -F":" '{print $NF}' | sed "s/ //g" | head -1 )
		reposLastPage=${reposLastPage//[$'\t\r\n ']}
		if [ -z ${reposLastPage} ]; then
    		reposLastPage=1
		fi
		i=1
		while [ ${i} -le ${reposLastPage} ]; do
			curl -H 'Content-Type: application/json' "${gitlab_api_pulls}&page=${i}"	2>/dev/null
			i=$( echo ${i} + 1 | bc )
		done | sed "s/\]\[/,/g" 	>${prjTmp}/pulls.${repoName}.json
        
        for key in $( cat ${prjTmp}/pulls.${repoName}.json | jq '. | keys | .[]' ); do
        	cat ${prjTmp}/pulls.${repoName}.json | jq .[${key}]	>${prjTmp}/pulls.key.json

        	pr_number=$( cat ${prjTmp}/pulls.key.json | jq '.iid' | sed "s/\"//g" )
			git_pr_url=$( cat ${prjTmp}/pulls.key.json | jq '.web_url' | sed "s/\"//g" )
            git_pull_created_at=$( cat ${prjTmp}/pulls.key.json | jq '.created_at' | sed "s/\"//g" )
            git_pr_creator=$( cat ${prjTmp}/pulls.key.json | jq '.author.username' | sed "s/\"//g" )
            
			gitlab_api_pr_reviews="${base_api}/projects/${gitlab_repo_id}/merge_requests/${pr_number}/approvals?private_token=${api_token}"
			
			curl --head -H 'Content-Type: application/json' "${gitlab_api_pr_reviews}"	2>/dev/null >${prjTmp}/pr_reviews.head.json
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
				curl -H 'Content-Type: application/json' "${gitlab_api_pr_reviews}&page=${i}"	2>/dev/null
				i=$( echo ${i} + 1 | bc )
			done | sed "s/\]\[/,/g" 	>${prjTmp}/pr_reviews.json

			cat ${prjTmp}/pr_reviews.json | jq '.approved_by[].user.username' | sed "s/\"//g" 2>/dev/null | while read line
            do
            	git_pr_reviewer=${line}
				echo "${git_pr_reviewer},APPROVED,${git_pr_url},${git_pull_created_at},${git_pr_creator}"	>>${prjTmp}/pr_reviews.csv
            done
			
        done
        
    fi

    num_prs_maxkey=$( cat ${prjTmp}/pulls.${repoName}.json | jq '. | keys | .[]' | tail -1 )
    if [[ -z ${num_prs_maxkey} ]]; then
        num_prs=0
    else
        num_prs=$( echo ${num_prs_maxkey} + 1 | bc )
    fi
    echo "${gitType} : ${base_api} : ${repoName} : PRs ${num_prs}"
    
    # sleep for 20s after scanning 5 repos
    if [ $( echo "${repo_cnt}%5" | bc ) -eq 0 ]; then
        sleep 20
        echo "sleep 20s..."
    fi
    repo_cnt=$( echo ${repo_cnt} + 1 | bc )
    echo ""
done

cp -p ${prjTmp}/pr_reviews.csv ${prjOut}/pr_reviews.csv
mkdir -p /var/lib/jenkins/git_pr_data
cp -p ${prjTmp}/pr_reviews.csv /var/lib/jenkins/git_pr_data/pr_reviews.csv
cp -p ${prjTmp}/pr_reviews.csv /var/lib/jenkins/git_pr_data/pr_reviews.good.$(date '+%Y-%m-%d').csv

