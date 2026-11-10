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
cts=$( date '+%Y%m%d' )
github_base_api="https://git.ouryahoo.com/api/v3"

# Below variables are stored as secret text(s) and are defined in the Jenkins Build Environment
#github_api_token=""

# Cleanup previous run
#
rm -rf ${prjTmp} ${prjOut} 2>/dev/null
mkdir -p ${prjTmp} ${prjOut} 

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

#
# loop through all repo names for the Org
for repoOwner in $( echo ${REPO_OWNERS_LIST} | sed "s/,/ /g" )
do
    # get Github active repositories (i.e. archived=false)
    #
    github_api_repos="${github_base_api}/orgs/${repoOwner}/repos"

    curl --head -H 'Content-Type: application/json' -H "Authorization: Bearer ${github_api_token}" "${github_api_repos}"	2>/dev/null >${prjTmp}/${repoOwner}.repos.head.json
    if [ $( cat ${prjTmp}/${repoOwner}.repos.head.json | egrep "HTTP/1.1 200 OK" | wc -l | sed "s/ //g" ) -ne 1 ]; then
	    echo "ERROR: Github Curl Failed (github_api_repos). Exit."
        exit 1
    fi
	
    reposLastPage=$( cat ${prjTmp}/${repoOwner}.repos.head.json | egrep "Link:" | egrep "last" | awk -F"/" '{print $NF}' | awk -F">" '{print $1}' | awk -F"=" '{print $NF}' )
    if [ -z ${reposLastPage} ]; then
        reposLastPage=1
    fi
    i=1
    while [ ${i} -le ${reposLastPage} ]; do
	    curl -H 'Content-Type: application/json' -H "Authorization: Bearer ${github_api_token}" "${github_api_repos}?page=${i}"	2>/dev/null
	    i=$( echo ${i} + 1 | bc )
    done | sed "s/\]\[/,/g" 	>${prjTmp}/${repoOwner}.repos.json
	
    repoNamesAll_array=($( cat ${prjTmp}/${repoOwner}.repos.json | jq '.[].full_name' | sed "s/\"//g" | sort -d | tr '\n' ' ' ))
    repoNamesActive_array=($( cat ${prjTmp}/${repoOwner}.repos.json | jq '.[] | select( "\(.archived)" == "false" ) | "\(.full_name)"' | sed "s/\"//g" | sort -d | tr '\n' ' ' ))

    printf "INFO: %-20s : active repos %d (total %d)\n" "${repoOwner}" "${#repoNamesActive_array[@]}" "${#repoNamesAll_array[@]}"
    
    #
    # Create output.csv file for all Orgs
    cat ${prjTmp}/${repoOwner}.repos.json | jq -r '.[] | [.full_name, .archived] | @csv' | sed "s/\"//g" >> ${prjOut}/output.csv

done

# create HTML report
#
echo "
<html>
`header`
<h3>OBI - Active Repositories Report : ${cts}</h3>
<body>
<table id="myTable" border="1">
<thead>
<tr>
<th bgcolor="lightblue">Repository Name</th>
<th bgcolor="lightblue">Archived Status</th>
</tr>
</thead>
<tbody>
">${prjOut}/output.html

cat ${prjOut}/output.csv | while read line
do
	repoName=$( echo ${line} | awk -F',' '{print $1}' )
	archivedStatus=$( echo ${line} | awk -F',' '{print $2}' )

    if [[ ${archivedStatus} == "true" ]]; then
        row_col="red"
    else
        row_col=""
    fi

echo "
<tr>
<td><font color=${row_col}>${repoName}</font></td>
<td><font color=${row_col}>${archivedStatus}</font></td>
</tr>
">>${prjOut}/output.html

done

echo "
</tbody>
</table>
</body>
</html>">>${prjOut}/output.html

set -x
