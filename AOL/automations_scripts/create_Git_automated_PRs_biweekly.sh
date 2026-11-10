#!/usr/bin/sh

#__author__ = 'anildalli'



##
## Script to Create Pull Request 
##
##
appDir="."
appTmp="${appDir}/tmp"
gitAPI="https://git.ouryahoo.com/api/v3"
assigneeLIST="jaluri,jvaidy,sayeev,pumkm,sfink14,svontiko,ppatel06,nbudico"


mkdir -p ${appDir}/tmp
rm ${appTmp}/*json ${appTmp}/*lst	2>/dev/null


echo ""
cts=$( date '+%Y%m%d%H%M' )
echo "[ ${cts} ] : Start... : prepare list of all repos"
echo ""


##
## get all repo names for the Org
##
##
urlRepo="${gitAPI}/orgs/OBI/repos"

curl --head -H 'Content-Type: application/json' -H "Authorization: Bearer ${GIT_TOKEN}" "${urlRepo}"	>${appTmp}/repos.head.json 2>/dev/null

if [[ $( cat ${appTmp}/repos.head.json | egrep "Status: 401 Unauthorized" | wc -l ) -eq 1 ]]; then
	echo "ERROR: Curl Status: 401 Unauthorized. Exiting..."
    exit 1
fi

reposLastPage=$( cat ${appTmp}/repos.head.json | egrep "Link:" | egrep "last" | awk -F"/" '{print $NF}' | awk -F">" '{print $1}' | awk -F"=" '{print $NF}' )
if [[ -z ${reposLastPage} ]]; then 
	reposLastPage=1;
fi

i=1
while [[ ${i} -le ${reposLastPage} ]]; do
	curl -H 'Content-Type: application/json' -H "Authorization: Bearer ${GIT_TOKEN}" "${urlRepo}?page=${i}"	2>/dev/null
	i=$( echo ${i} + 1 | bc )
done | sed "s/\]\[/,/g" 	>${appTmp}/repos.json
	
cat ${appTmp}/repos.json | egrep "full_name" | awk '{print $2}' | sed "s/\"//g" | sed "s/,//g" >${appTmp}/repo.names.lst

if [[ -s ${appTmp}/repo.names.lst ]]; then
	numRepos=$( cat ${appTmp}/repo.names.lst | wc -l )
else
	numRepos=NA
fi

echo ""
echo "Total number of  Repos : ${numRepos}"
echo ""

if [[ ${numRepos} == "NA" ]]; then
	echo "ERROR: 0 repos listed. Exiting..."
    exit 1
fi

cts=$( date '+%Y%m%d%H%M' )
echo "[ ${cts} ] : Start... : prepare list of all repos having pipeline branch"
echo ""


##
## get repo names having pipeline branch
##
##
cat ${appTmp}/repo.names.lst |  while read repoName
do
	urlRepoPL="${gitAPI}/repos/${repoName}/branches/pipeline"
	
	curl -H 'Content-Type: application/json' -H "Authorization: Bearer ${GIT_TOKEN}" "${urlRepoPL}"	>${appTmp}/repo.pl.json 2>/dev/null

	if [[ $( cat ${appTmp}/repo.pl.json | egrep "name" | egrep "pipeline" | wc -l ) -eq 1 ]];  then
		echo "... this repo has pipeline branch : ${repoName}"
		echo ${repoName}  	>>${appTmp}/repo.names.pl.lst
	fi
done

if [[ -s ${appTmp}/repo.names.pl.lst ]]; then
        numReposPL=$( cat ${appTmp}/repo.names.pl.lst | wc -l )
else
	numReposPL=NA
fi

echo ""
echo "Number of Repos having pipeline branch : ${numReposPL}"
echo ""

if [[ ${numReposPL} == "NA" ]]; then
	echo "ERROR: 0 repos having pipeline listed. Exiting..."
    exit 1
fi

cts=$( date '+%Y%m%d%H%M' )
echo "[ ${cts} ] : Start... : compare commits between pipeline branch and main"
echo ""


##
## commits compare pipeline branch to main
##
##
cat ${appTmp}/repo.names.pl.lst | while read repoNamePL
do
	urlCommitsCompare="${gitAPI}/repos/${repoNamePL}/compare/main...pipeline"

	curl -H 'Content-Type: application/json' -H "Authorization: Bearer ${GIT_TOKEN}" "${urlCommitsCompare}"	>${appTmp}/repo.plcc.json 2>/dev/null

	numCommitsAheadBy=$( cat ${appTmp}/repo.plcc.json | egrep "ahead_by" | awk -F":" '{print $NF}' | awk -F"," '{print $1}' | sed "s/ //g" | head -1 )
  #echo "${repoNamePL}:numCommitsAheadBy:$numCommitsAheadBy:"
  if [[ ! -z ${numCommitsAheadBy} ]]; then
	  if [[ ${numCommitsAheadBy} -ge 1 ]];  then
		  echo "... pipeline branch : ${repoNamePL} is ahead by :${numCommitsAheadBy}: commits"
		  echo "${repoNamePL}"	>>${appTmp}/repo.names.pl.aheadby.lst
	  fi
  fi
done

if [[ -s ${appTmp}/repo.names.pl.lst ]]; then
        numReposPLahead=$( cat ${appTmp}/repo.names.pl.aheadby.lst | wc -l )
else
        numReposPLahead=NA
fi

echo ""
echo "Number of Repos where pipeline branch commits are ahead to main : ${numReposPLahead}"
echo ""
cts=$( date '+%Y%m%d%H%M' )
echo "[ ${cts} ] : Start... : create pull requests followed by review requests"
echo ""


##
## create a pull request release number
##
##
cat ${appTmp}/repo.names.pl.lst | while read repoNamePL
do
	urlListPR="${gitAPI}/repos/${repoNamePL}/pulls?state=all"

	curl -H 'Content-Type: application/json' -H "Authorization: Bearer ${GIT_TOKEN}" "${urlListPR}" >${appTmp}/pr.list.json 2>/dev/null 
	cat ${appTmp}/pr.list.json | jq ".[]|.title"
done >${appTmp}/all.titles.lst

yrmo=$( date '+%y.%m.' )
last_relnum=$( cat "${appTmp}/all.titles.lst" 2>/dev/null | egrep "Pull request for prod release" | sed "s/\"//g" | awk '{print $6}' | egrep "${yrmo}" | sort -n | tail -1 )
if [[ $( echo "${last_relnum}" | egrep "${yrmo}" | wc -l ) -eq 1 ]]; then
	cur_relnum=$( echo "${last_relnum}" | egrep "${yrmo}" | sed s"/${yrmo}//g" )
	new_relnum=$( echo ${cur_relnum} + 1 | bc )
else
	new_relnum=1
fi
prReleaseNum="${yrmo}${new_relnum}"
echo ""
echo "Title: Pull request for prod release ${prReleaseNum}"
echo ""


##
## create a pull request followed by review request
##
##
cat ${appTmp}/repo.names.pl.aheadby.lst | while read repoNamePR
do
	echo ""
	echo "Repo Name       : ${repoNamePR}"
	urlPR="${gitAPI}/repos/${repoNamePR}/pulls" 
	dataPR="{\"title\": \"Pull request for prod release ${prReleaseNum}\",\"head\": \"pipeline\",\"base\": \"main\"}"
	curl -X POST -H 'Content-Type: application/json' -H "Authorization: Bearer ${GIT_TOKEN}" -H 'Accept: application/vnd.github.shadow-cat-preview+json' -d "${dataPR}" "${urlPR}"	>${appTmp}/repo.PR.log	2>/dev/null

	prURL=$( cat ${appTmp}/repo.PR.log | jq .url )
	if [[ ${prURL} == null ]]; then
		if [[ $( cat ${appTmp}/repo.PR.log | jq .documentation_url | egrep "developer.github.com" | wc -l ) -eq 1 ]]; then
			prMsg=$( cat ${appTmp}/repo.PR.log | jq .message )
			echo "*** ERROR/WARNING: pull request not created : ${prMsg}"
			cat ${appTmp}/repo.PR.log | jq .errors
		fi
	else
		echo "Pull Request URL: ${prURL}"
		prNum=$( echo ${prURL} | sed "s/#//g" | awk -F"/" '{print $NF}' | sed "s/\"//g" )
		echo "... created pull request # ${prNum}"
		echo "...... Start : update PR with assignees"

		urlUpdatePRAssignees="${gitAPI}/repos/${repoNamePR}/issues/${prNum}/assignees"
		dataUpdatePRAssignees=$( echo ${assigneeLIST} | sed 's/ //g' | sed 's/,/\\\",\\\"/g' | sed 's/^/\\\"/g' | sed 's/$/\\\"/g' | sed 's/^/{\\\"assignees\\\": [/g' | sed 's/$/]}/g')
		dataUpdatePRAssigneesVal=$( eval echo $dataUpdatePRAssignees )
		#dataUpdatePRAssignees=$( echo ${assigneeLIST} | sed 's/ //g' | sed 's/,/\\\",\\\"/g' | sed 's/^/\\\"/g' | sed 's/$/\\\"/g' | sed 's/^/\"{\\\"assignees\\\": [/g' | sed 's/$/]}\"/g' )
		curl -X POST -H 'Content-Type: application/json' -H "Authorization: Bearer ${GIT_TOKEN}" -H 'Accept: application/vnd.github.shadow-cat-preview+json' -d "${dataUpdatePRAssigneesVal}" "${urlUpdatePRAssignees}"	>${appTmp}/repo.UpdatePRAssignees.log  2>/dev/null

		prAssigneesURL=$( cat ${appTmp}/repo.UpdatePRAssignees.log | jq .url )
		if [[ ${prAssigneesURL} == null ]]; then
			if [[ $( cat ${appTmp}/repo.UpdatePRAssignees.log | jq .documentation_url | egrep "developer.github.com" | wc -l ) -eq 1 ]]; then
				prMsg=$( cat ${appTmp}/repo.UpdatePRAssignees.log | jq .message )
				echo "****** ERROR/WARNING: update PR with Assignees : ${prMsg}"
        			cat ${appTmp}/repo.UpdatePRAssignees.log | jq .errors
			fi
		else
			echo "SUCCESS: PR is updated with assignees : ${prAssigneesURL}"
		fi
	fi
	echo ""
done


echo ""
cts=$( date '+%Y%m%d%H%M' )
echo "[ ${cts} ] : Complete..."
echo ""
