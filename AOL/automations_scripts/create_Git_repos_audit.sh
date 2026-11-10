#!/usr/bin/sh

#__author__ = 'anildalli'



##
## Script to scan OBI,OATH-COMMERCE,CCARE,SCC-devops,GAP,CLIENT,CLIENTDEV,WAS,MCP repos
## not having either default main branch or not protected or having less than 2 approvers to review
##
##
appDir="."
appTmp="${appDir}/tmp"
appOut="${appDir}/output"
gitAPI="https://git.ouryahoo.com/api/v3"
currDate=$( date '+%Y-%m-%d' )
## defined via jenkins
#GIT_TOKEN=
#repoOwnersList="OBI,OATH-COMMERCE,CCARE,SCC-devops,GAP,CLIENT,CLIENTDEV,WAS,MCP"

mkdir -p ${appTmp}
mkdir -p ${appOut}
rm ${appTmp}/*json ${appTmp}/*lst ${appTmp}/*csv ${appTmp}/*txt	${appTmp}/*html 2>/dev/null


echo ""
cts=$( date '+%Y%m%d%H%M' )
echo "[ ${cts} ] : Start... "
echo ""


##
## get all repo names for the Org
##
##

for repoOwner in $( echo ${REPO_OWNERS_LIST} | sed "s/,/ /g" )
do
	echo ""
	#echo "Repo Owner : ${repoOwner}"
	urlRepo="${gitAPI}/orgs/${repoOwner}/repos"

	echo "### INFO: Running APIs for auditing GIT Repositories for Org - ${repoOwner}"
	curl --head -H 'Content-Type: application/json' -H "Authorization: Bearer ${GIT_TOKEN}" "${urlRepo}"	>${appTmp}/repos.${repoOwner}.head.json 2>/dev/null

	if [ $( cat ${appTmp}/repos.${repoOwner}.head.json | egrep "Status: 401 Unauthorized" | wc -l | sed "s/ //g" ) -eq 1 ]; then
		echo "ERROR: Curl Status: 401 Unauthorized. Exiting..."
    		exit 1
	fi
	
	reposLastPage=1
	reposLastPage=$( cat ${appTmp}/repos.${repoOwner}.head.json | egrep "Link:" | egrep "last" | awk -F"/" '{print $NF}' | awk -F">" '{print $1}' | awk -F"=" '{print $NF}' )
	if [ -z ${reposLastPage} ]; then 
		reposLastPage=1;
	fi

	i=1
	while [ ${i} -le ${reposLastPage} ]; do
		curl -H 'Content-Type: application/json' -H "Authorization: Bearer ${GIT_TOKEN}" "${urlRepo}?page=${i}"	2>/dev/null
		i=$( echo ${i} + 1 | bc )
	done | sed "s/\]\[/,/g" 	>${appTmp}/repos.${repoOwner}.json
	
	cat ${appTmp}/repos.${repoOwner}.json | egrep "full_name" | awk '{print $2}' | sed "s/\"//g" | sed "s/,//g" >${appTmp}/repos.${repoOwner}.all_names.lst
	cat ${appTmp}/repos.${repoOwner}.json | jq '.[] | select( "\(.archived)" == "false" )' | egrep "full_name" | awk '{print $2}' | sed "s/\"//g" | sed "s/,//g" >${appTmp}/repos.${repoOwner}.names.lst

	numRepos=0
	if [ -s ${appTmp}/repos.${repoOwner}.names.lst ]; then
		numRepos=$( cat ${appTmp}/repos.${repoOwner}.names.lst | wc -l | sed "s/ //g" )
	else
		numRepos=NA
	fi
	
	numAllRepos=0
	if [ -s ${appTmp}/repos.${repoOwner}.all_names.lst ]; then
		numAllRepos=$( cat ${appTmp}/repos.${repoOwner}.all_names.lst | wc -l | sed "s/ //g" )
	else
		numAllRepos=NA
	fi

	echo "### INFO: Active Repos (of Total Repos) : ${numRepos} (of ${numAllRepos}) for Org - ${repoOwner}"

	if [ ${numRepos} == "NA" ]; then
		echo "ERROR: 0 repos listed. Exiting..."
    		exit 1
	fi

	cat ${appTmp}/repos.${repoOwner}.json | egrep "full_name|default_branch" | sed "s/\"//g" | sed "s/ //g" 	>${appTmp}/repos.${repoOwner}.default.txt
	
	##
	## repo names not having either default main branch or not protected or having less than 2 approvers to review
	##

	cat ${appTmp}/repos.${repoOwner}.names.lst | while read repoName
	do
		defaultBranch=$( egrep -A1 "${repoName}," ${appTmp}/repos.${repoOwner}.default.txt | egrep "default_branch" | awk -F":" '{print $2}' | awk -F"," '{print $1}' )
		if [ -z ${defaultBranch} ]; then
			defaultBranch=NA
		fi

		if [ ${defaultBranch} == "main" ]; then 		
			urlRepoPL="${gitAPI}/repos/${repoName}/branches/${defaultBranch}"
			curl -H 'Content-Type: application/json' -H "Authorization: Bearer ${GIT_TOKEN}" "${urlRepoPL}"	>${appTmp}/repo.main.json 2>/dev/null

			if [ $( cat ${appTmp}/repo.main.json | egrep "Branch not found" | wc -l | sed "s/ //g" ) -eq 1 ]; then
				defaultBranch=EmptyRepo
			fi
			if [ $( cat ${appTmp}/repo.main.json | sed "s/\"//g" | egrep "protected:" | wc -l | sed "s/ //g" ) -eq 1 ];  then
				protected_status=$( cat ${appTmp}/repo.main.json | sed "s/\"//g" | egrep "protected:" | sed "s/ //g" | awk -F":" '{print $2}' | awk -F"," '{print $1}' )
			else
				protected_status=NA
			fi
		fi

		#rn=$( echo $repoName | awk -F"/" '{print $2}' )        	
		urlBranchProtection="${gitAPI}/repos/${repoName}/branches/${defaultBranch}/protection"
        	curl -H 'Content-Type: application/json' -H "Accept: application/vnd.github.luke-cage-preview+json" -H "Authorization: Bearer ${GIT_TOKEN}" "${urlBranchProtection}" >${appTmp}/repo.branch_protection.json 2>/dev/null
		#cp -p ${appTmp}/repo.branch_protection.json ${appTmp}/repo.branch_protection.${rn}.json

        	approversCount=$( cat ${appTmp}/repo.branch_protection.json | egrep "required_approving_review_count" | sed "s/\"//g" | sed "s/,//g" | awk -F":" '{print $2}' | sed "s/ //g" )
		if [ -z ${approversCount} ]; then
			if [ $( cat ${appTmp}/repo.branch_protection.json | sed "s/\"//g" | egrep "message: Not Found," | wc -l | sed "s/ //g" ) -eq 1 ]; then
				approversCount=99
			else
				approversCount=0
			fi
		fi
		if [ ${approversCount} -lt 2 ]; then
			approversCountStatus=less-than-2-approvers
		elif [ ${approversCount} -eq 99 ]; then
			approversCountStatus=no-access
		else
			approversCountStatus=2-or-more-approvers
		fi

		echo "${repoName},${defaultBranch},${protected_status},${approversCountStatus}(${approversCount})"
	done	| tee -a ${appTmp}/repos.${repoOwner}.fullresult.csv

	if [ -s ${appTmp}/repos.${repoOwner}.fullresult.csv ]; then

        	cat ${appTmp}/repos.${repoOwner}.fullresult.csv | egrep -v ",main,|,NA,|,EmptyRepo,"	>${appTmp}/repos.${repoOwner}.filteredresult.csv
		cat ${appTmp}/repos.${repoOwner}.fullresult.csv | egrep ",false,"			>>${appTmp}/repos.${repoOwner}.filteredresult.csv
		cat ${appTmp}/repos.${repoOwner}.fullresult.csv | egrep ",less-than-2-approvers"	>>${appTmp}/repos.${repoOwner}.filteredresult.csv

        	numReposDefaultCheckFail=$( cat ${appTmp}/repos.${repoOwner}.filteredresult.csv | sort -u | wc -l | sed "s/ //g" )
	else
		numReposDefaultCheckFail=0
	fi

	echo "INFO: ${numReposDefaultCheckFail} repos failed audit (not having default branch as main, or not protected, or not having 2 approvers for pull request review)"

done

cat ${appTmp}/repos.*.fullresult.csv | sort -u | sed "s/less-than-2-approvers//g" | sed "s/2-or-more-approvers//g" | sed "s/(99)//g" | sed "s/(//g" | sed "s/)//g" 	>${appTmp}/repos.fullresult.final.csv
cat ${appTmp}/repos.*.filteredresult.csv | sort -u | sed "s/less-than-2-approvers//g" | sed "s/2-or-more-approvers//g" | sed "s/(99)//g" | sed "s/(//g" | sed "s/)//g" 	>${appTmp}/repos.filteredresult.final.csv

echo "<html>
<head>
<style>
table, th, td {
  border: 1px solid black;
  border-collapse: collapse;
}
</style>
</head>
<h3>Git Repos Report - ${currDate}</h3>
<table>
<tr>
<th>Repo Name</th>
<th>Default Branch</th>
<th>Protected</th>
<th>Approvers<br/>for Review</th>
</tr>"  >${appOut}/reposCompleteReport.html

cat ${appTmp}/repos.fullresult.final.csv | while read repoLine
do
	col1=$( echo ${repoLine} | awk -F"," '{print $1}' )
	col2=$( echo ${repoLine} | awk -F"," '{print $2}' )
	col3=$( echo ${repoLine} | awk -F"," '{print $3}' )
	col4=$( echo ${repoLine} | awk -F"," '{print $4}' )
        col4_col=""
        if [ ${col4} -ne 2 ]; then
		col4_col=red
        fi

echo "<tr>
<td>${col1}</td>
<td>${col2}</td>
<td>${col3}</td>
<td bgcolor=${col4_col}>${col4}</td>
</tr>"	>>${appOut}/reposCompleteReport.html

done

echo "</table></body></html>"	>>${appOut}/reposCompleteReport.html

if [ -s ${appTmp}/repos.filteredresult.final.csv ]; then
       	numReposDefaultCheckFailAll=$( cat ${appTmp}/repos.filteredresult.final.csv | wc -l | sed "s/ //g" )
else
	numReposDefaultCheckFailAll=0
fi

#echo ""
#echo ""
#echo "INFO: ${numReposDefaultCheckFail} repos failed audit (not having default branch as main, or not protected, or not having 2 approvers for pull request review)"
#echo ""
#echo ""

echo "<html>
<head>
<style>
table, th, td {
  border: 1px solid black;
  border-collapse: collapse;
}
</style>
</head>
<h3>Git Repos Anomaly Report - ${currDate}</h3>" >${appOut}/reposAnomalyReport.html

if [ ${numReposDefaultCheckFailAll} -ge 1 ]; then
	echo "ERROR: ${numReposDefaultCheckFailAll} repos not compliant. Exiting..."

echo "<table>
<tr>
<th>Repo Name (exclude archived repos)</th>
<th>Default Branch</th>
<th>Protected</th>
<th>Approvers<br/>for Review</th>
</tr>"	>>${appOut}/reposAnomalyReport.html

cat ${appTmp}/repos.filteredresult.final.csv | while read repoLine
do
	col1=$( echo ${repoLine} | awk -F"," '{print $1}' )
	col2=$( echo ${repoLine} | awk -F"," '{print $2}' )
	col3=$( echo ${repoLine} | awk -F"," '{print $3}' )
	col4=$( echo ${repoLine} | awk -F"," '{print $4}' )
        col4_col=""
        if [ ${col4} -ne 2 ]; then
		col4_col=red
        fi

echo "<tr>
<td>${col1}</td>
<td>${col2}</td>
<td>${col3}</td>
<td bgcolor=${col4_col}>${col4}</td>
</tr>"	>>${appOut}/reposAnomalyReport.html

done

echo "</table>"	>>${appOut}/reposAnomalyReport.html

else

echo "<br><h3 style=\"color:MediumSeaGreen\">All Good!!!</h3><br>"	>>${appOut}/reposAnomalyReport.html

fi
echo "</body></html>"	>>${appOut}/reposAnomalyReport.html

echo ""
cts=$( date '+%Y%m%d%H%M' )
echo "[ ${cts} ] : End"
echo ""


