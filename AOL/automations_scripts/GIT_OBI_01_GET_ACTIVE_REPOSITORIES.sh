##
## 
## Get list of Active Repos for OBI - Github and Gitlab
##
## Active Repositories means archived=false
##

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
if [ ! -f ${targetDir}/repos.active ]; then
	touch ${targetDir}/repos.active
fi


# Header function called while building HTML page
#
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


## # get Gitlab active repositories (i.e. archived=false)
## #
## gitlab_api_repos="${gitlab_base_api}/projects?private_token=${gitlab_api_token}&per_page=100"
## 
## curl --head -H 'Content-Type: application/json' "${gitlab_api_repos}"	2>/dev/null >${prjTmp}/repos.head.json
## if [ $( cat ${prjTmp}/repos.head.json | egrep "HTTP/1.1 200 OK" | wc -l | sed "s/ //g" ) -ne 1 ]; then
## 	echo "ERROR: Gitlab Curl Failed (gitlab_api_repos). Exit."
##     exit 1
## fi
## 
## reposLastPage=$( cat ${prjTmp}/repos.head.json | egrep "X-Total-Pages:" | awk -F":" '{print $NF}' | sed "s/ //g" | head -1 )
## reposLastPage=${reposLastPage//[$'\t\r\n ']}
## if [ -z ${reposLastPage} ]; then
##     reposLastPage=1
## fi
## i=1
## while [ ${i} -le ${reposLastPage} ]; do
## 	curl -H 'Content-Type: application/json' "${gitlab_api_repos}&page=${i}"	2>/dev/null
## 	i=$( echo ${i} + 1 | bc )
## done | sed "s/\]\[/,/g" 	>${prjTmp}/repos.json
## 
## repoNamesAll_array=($( cat ${prjTmp}/repos.json | jq '.[].path_with_namespace' | sed "s/\"//g" | sed "s/ //g" | egrep -v "AlexanderLepekhin|PuneetSharma" | sort -d | tr '\n' ' ' ))
## repoNamesActive_array=($( cat ${prjTmp}/repos.json | jq '.[] | select( "\(.archived)" == "false" ) | "\(.path_with_namespace)#\(.id)"' | sed "s/\"//g" | sed "s/ //g" | egrep -v "AlexanderLepekhin|PuneetSharma" | sort -d | tr '\n' ' ' ))    
## 
## for repoFullNameId in ${repoNamesActive_array[@]}; do
##     repoNameId=$( echo "${repoFullNameId}" | awk -F'/' '{print $NF}' )
##     repoNamesActive_array_gl+=(${repoNameId})
## done
## 
## echo "INFO: Gitlab - active repos ${#repoNamesActive_array[@]} (total ${#repoNamesAll_array[@]})"


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

echo "INFO: Github - active repos ${#repoNamesActive_array[@]} (total ${#repoNamesAll_array[@]})"


# create list of project repositories to scan all PRs
#
## for repoName in ${repoNamesActive_array_gl[@]}; do
##     repoNamesActive_array_gl_map+=(${repoName}":gitlab")
## done

for repoName in ${repoNamesActive_array_gh[@]}; do
    repoNamesActive_array_gh_map+=(${repoName}":github")
done

## project_repos_map_array=("${repoNamesActive_array_gl_map[@]}" "${repoNamesActive_array_gh_map[@]}")
project_repos_map_array=("${repoNamesActive_array_gh_map[@]}")

## echo "INFO: Gitlab+Github - ${#project_repos_map_array[@]} repos to be scanned for all PRs"
echo "INFO: Github - ${#project_repos_map_array[@]} repos to be scanned for all PRs"


# loop through project repositories and prepare list of active repositories
#
for repoNameGitType in ${project_repos_map_array[@]}; do
    repoName=$( echo "${repoNameGitType}" | awk -F':' '{print $1}' )
    gitType=$( echo "${repoNameGitType}" | awk -F':' '{print $2}' )

	echo "${gitType},${repoName}"
done >${prjOut}/repos.active

if [ -s ${prjOut}/repos.active ]; then
    if [ $(cat ${prjOut}/repos.active | wc -l ) -ne $( cat ${targetDir}/repos.active | wc -l ) ]; then
        echo "INFO: Change in Active Repos compared to last run. Backup and over-writing the previous file in target directory - ${targetDir}."
        ls -l ${targetDir}/repos.active ${prjOut}/repos.active
        cp -p ${targetDir}/repos.active ${targetDir}/repos.active.${cts}
        mv ${prjOut}/repos.active ${targetDir}/repos.active
    else
    	echo "INFO: No change in Active Repos compared to last run."
    fi
fi


# create HTML report
#
echo "
<html>
<h3>OBI - Active Repositories Report : ${cts}</h3>
<body>
<table id="myTable" border="1">
<thead>
<tr>
<th bgcolor="lightblue">Git Type</th>
<th bgcolor="lightblue">Repository Name (#ID)</th>
</tr>
</thead>
<tbody>
">${prjOut}/repos.active.html

cat ${targetDir}/repos.active | while read line
do
	gitType=$( echo ${line} | awk -F',' '{print $1}' )
	repoName=$( echo ${line} | awk -F',' '{print $2}' )

echo "
<tr>
<td>${gitType}</td>
<td>${repoName}</td>
</tr>
">>${prjOut}/repos.active.html

done

echo "
</tbody>
</table>
</body>
</html>">>${prjOut}/repos.active.html

set -x
