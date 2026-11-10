#!/usr/bin/sh

#
# author: anildalli
# 
# description: Scan through https://ministryofcode.corp.yahoo.com/code_review_data/daily/index.html page.
#              Prepare a customized report for L3 summary, L4 Summary and Repo Summary for L3 (Brendan Jennings).
#



# update l3Name value if you need to run the same report for some other l3
#
l3Name=brenmjenn


# update appDir value if you need to run in some other server/environment
#
appDir="/home/anildall/moc_email_report"
appTmp="${appDir}/tmp"
appOut="${appDir}/reports"
mkdir -p ${appTmp}
mkdir -p ${appOut}


# email info 
#
TO_EMAIL="jagadeesh.aluri@yahooinc.com,umesh.chhatre@yahooinc.com,v.jayaraman@yahooinc.com,anil.dalli@yahooinc.com"
#TO_EMAIL="anil.dalli@yahooinc.com"
FROM_EMAIL="do-not-reply@yahooinc.com"


# daily index url information that would be used to pull the required data
#
url_dailyIdx="https://ministryofcode.corp.yahoo.com/code_review_data/daily/index.html"


# pull daily index page data to check for last date for available report
# also determine the date to run the report
#
curl -L ${url_dailyIdx}           >${appTmp}/dailyIdx.raw.html      2>/dev/null
curl_status=$?
if [ ${curl_status} -ne 0 ]; then
        echo "ERROR: Curl failed - ${url_dailyIdx}"
        exit 1
fi

lastDatePage=$( egrep -A1 "<tbody id=\"data\">" ${appTmp}/dailyIdx.raw.html | tail -1 | sed "s/\"//g" | awk -F"=" '{print $2}' | awk -F">" '{print $1}' )
if [ -z ${lastDatePage} ]; then
	echo "ERROR: Not able to find last date on Ministry of Code index page"
	exit 1
fi

lastDateReport=$( ls -1 ${appOut}/*html 2>/dev/null | awk -F"/" '{print $NF}' | tail -1 | awk -F"." '{print $2}' )
if [ -z ${lastDateReport} ]; then
	echo "WARNING: No reports found.. running the report for current date -15 days"
	lastDateReport=$( date -d "-15 days" '+%Y-%m-%d' 2>/dev/null )
fi
	
ExpectedDateReport=$( date -d "-1 days" '+%Y-%m-%d' 2>/dev/null )

echo "INFO: Last date on Ministry of Code index page : ${lastDatePage}"
echo "INFO: Last date of report generation           : ${lastDateReport}"
echo "INFO: Expected date of report generation       : ${ExpectedDateReport}"

if [ $( echo ${lastDateReport} | sed "s/-//g" ) -lt $( echo ${lastDatePage} | sed "s/-//g" ) ]; then
	reportGenDate=$( date -d "+1 day ${lastDateReport}" '+%Y-%m-%d' 2>/dev/null )
	echo "INFO: Running the report for ${reportGenDate}"
else
	echo "INFO: Do not run the report..."
	exit 0
fi


# name of html report output html file as body for sending email 
#
RPT_BODY="${appOut}/moc_report.${reportGenDate}.html"


# function to email the report
#
function email_report_func(){

export CONTENT="${RPT_BODY}"
(
echo -e "Subject: ${RPT_SUBJ}"
echo -e "From: ${FROM_EMAIL}"
echo -e "To: ${TO_EMAIL}"
echo -e "MIME-Version: 1.0"
echo -e "Content-Type: text/html"
echo -e "Content-Disposition: inline"
cat ${RPT_BODY}
) | /usr/sbin/sendmail ${TO_EMAIL}

}


# l3, l4, repo url information that would be used to pull the required data
#
url_l3Summ="https://ministryofcode.corp.yahoo.com/code_review_data/daily/${reportGenDate}/l3_summary.html"
url_l4Summ="https://ministryofcode.corp.yahoo.com/code_review_data/daily/${reportGenDate}/l4_summary.html"
url_l3RepoSumm="https://ministryofcode.corp.yahoo.com/code_review_data/daily/${reportGenDate}/repository_summary.html#l3_${l3Name}"


# pull l3 summary, and prepare report if not compliant
#
curl -L ${url_l3Summ} 		>${appTmp}/l3Summ.raw.html	2>/dev/null
curl_status=$?
if [ ${curl_status} -ne 0 ]; then
	echo "ERROR: Curl failed - ${url_l3Summ}"
	exit 1
fi

echo "<html>
<head>
<style>
table, th, td {
  border: 1px solid black;
  border-collapse: collapse;
}
</style>
</head>
<h2>Code Review Summary - ${reportGenDate}</h2>"	>${appTmp}/moc_report.html


egrep -A13 "tr id=\"${l3Name}\"" ${appTmp}/l3Summ.raw.html | egrep -v "${l3Name}-index|${l3Name}-drill-down|${l3Name}-repos|title=" | sed -e 's/^[ \t]*//' | sed "s/^<\/td>//g" | sed "/^$/d" | sed "s/ class=\"a-unstyled\"//g" | sed "s/ target=\"_blank\"//g" | sed "s/ class=\"text-right\"//g" >${appTmp}/moc_report.l3.tmp

l3Score=$( cat ${appTmp}/moc_report.l3.tmp | egrep "${l3Name}-score" | awk -F">" '{print $2}' | awk -F"<" '{print $1}' | sed "s/%//g" )
if [ -z ${l3Score} ]; then
	l3Score=100
fi
if [ ${l3Score} -ne 100 ]; then

	RPT_SUBJ="${l3Score}% score : Code Review Summary ${reportGenDate}"
	echo "<br>
	<h3>L3 Summary</h3>
	<table>
	<tr>
	<th>L2</th>
	<th>L3</th>
	<th>Total<br/>Pushes</th>
	<th>Reviewed<br/>Pushes</th>
	<th>Code<br/>Review<br/>Score</th>
	</tr>" | sed "s/^	//g"	>>${appTmp}/moc_report.html

        cat ${appTmp}/moc_report.l3.tmp	>>${appTmp}/moc_report.html
else
	RPT_SUBJ="Hurray.. All Good : Code Review Summary ${reportGenDate}"
	echo "<br><h3 style=\"color:MediumSeaGreen\">100% compliant</h3><br>"	>>${appTmp}/moc_report.html
	echo "</body></html>"       >>${appTmp}/moc_report.html

	cp -p ${appTmp}/moc_report.html ${appOut}/moc_report.${reportGenDate}.html

	echo ""
	echo "SUBJECT: ${RPT_SUBJ}"
	echo "BODY: ${RPT_BODY}"
	echo ""

	# send email for being compliant
	email_report_func
	exit 0
fi

echo "</table>"	>>${appTmp}/moc_report.html



# pull l4 summary, and prepare report if not compliant
#
curl -L ${url_l4Summ}	 	>${appTmp}/l4Summ.raw.html	2>/dev/null
curl_status=$?
if [ ${curl_status} -ne 0 ]; then
	echo "ERROR: Curl failed - ${url_l4Summ}"
	exit 1
fi

echo "<br>
<h3>L4 Summary</h3>
<table>
<tr>
<th>L2</th>
<th>L3</th>
<th>L4</th>
<th>Total<br/>Pushes</th>
<th>Reviewed<br/>Pushes</th>
<th>Code<br/>Review<br/>Score</th>
</tr>" >>${appTmp}/moc_report.html

egrep "${l3Name}" ${appTmp}/l4Summ.raw.html | egrep index | awk -F"id=" '{print $2}' | awk -F">" '{print $1}' | sed "s/-index//g" | sed "s/\"//g" | while read l4Name
do
	egrep -A14 "id=\"${l4Name}\"" ${appTmp}/l4Summ.raw.html | egrep -v "${l4Name}-index|${l4Name}-drill-down|${l4Name}-repos|title=" | sed -e 's/^[ \t]*//'	| sed "s/^<\/td>//g" | sed "/^$/d" | sed "s/ class=\"a-unstyled\"//g" | sed "s/ target=\"_blank\"//g" | sed "s/ class=\"text-right\"//g"	>${appTmp}/moc_report.l4.tmp
	l4Score=$( cat ${appTmp}/moc_report.l4.tmp | egrep "${l4Name}-score" | awk -F">" '{print $2}' | awk -F"<" '{print $1}' | sed "s/%//g" )
	if [ ${l4Score} -ne 100 ]; then
        	cat ${appTmp}/moc_report.l4.tmp       >>${appTmp}/moc_report.html
	fi
done
echo "</table>"	>>${appTmp}/moc_report.html


# pull repo summary, and prepare report if not compliant
#
curl -L ${url_l3RepoSumm} 	>${appTmp}/l3RepoSumm.raw.html	2>/dev/null
curl_status=$?
if [ ${curl_status} -ne 0 ]; then
	echo "ERROR: Curl failed - ${url_l3RepoSumm}"
	exit 1
fi

echo "<br>
<h3>Repo Summary</h3>
<table>
<tr>
<th>L2</th>
<th>L3</th>
<th>L4</th>
<th>L5</th>
<th>Code<br/>Review<br/>Owner</th>
<th>Repository</th>
<th>Total<br/>Pushes</th>
<th>Reviewed<br/>Pushes</th>
<th>Code<br/>Review<br/>Score</th>
<th>Pushes<br/>From<br/>Gerrit</th>
<th>Pushes<br/>Without PR</th>
<th>Pushes<br/>With<br/>Unreviewed<br/>PR</th>
<th>Pushes<br/>With<br/>Reviewed<br/>PR</th>
</tr>" >>${appTmp}/moc_report.html

egrep -n -B4 "l3_${l3Name}" ${appTmp}/l3RepoSumm.raw.html | egrep "<tr " | awk '{print $1","$NF}' | sed "s/id=//g" | sed "s/>//g" | sed "s/\"//g" | sed "s/-,/,/g" >${appTmp}/moc_report.reponames.ln.tmp

cat ${appTmp}/moc_report.reponames.ln.tmp | while read repoLine
do
	repoName=$( echo ${repoLine} | awk -F"," '{print $2}' )
	startLine=$( echo ${repoLine} | awk -F"," '{print $1}' )
	endLineTmp=$( egrep -A1 "${startLine}" ${appTmp}/moc_report.reponames.ln.tmp | tail -1 | awk -F"," '{print $1}' )
	endLine=$( echo "${endLineTmp} -1" | bc )

	if [ ${endLineTmp} -eq ${startLine} ]; then
		endLine=$(echo "${startLine} + 90" | bc )
	fi
	sed -n "${startLine}","${endLine}"p ${appTmp}/l3RepoSumm.raw.html | sed -e 's/^[ \t]*//' | sed "s/ class=\"a-unstyled\"//g" | sed "s/ target=\"_blank\"//g" | sed "s/ class=\"text-right\"//g" | egrep -v "<span|span>"  >${appTmp}/moc_report.reposumm.tmp
	if [ $( cat ${appTmp}/moc_report.reposumm.tmp | egrep "<tr " | wc -l ) -ne 1 ]; then
		lastRepoDelSLine=$( cat ${appTmp}/moc_report.reposumm.tmp | egrep -n "<tr " | tail -1 | awk -F":" '{print $1}' )
		lastRepoDelELine=$( echo "${lastRepoDelSLine} + 30" | bc )
		cat ${appTmp}/moc_report.reposumm.tmp | sed -e "${lastRepoDelSLine}","${lastRepoDelELine}"d	>${appTmp}/moc_report.reposumm.tmp.tmp
		mv ${appTmp}/moc_report.reposumm.tmp.tmp ${appTmp}/moc_report.reposumm.tmp
	fi

	repoScore=$( cat ${appTmp}/moc_report.reposumm.tmp | egrep -A1 "code-review-score" | tail -1 | sed "s/ //g" | sed "s/%//g" )
	if [ ${repoScore} -ne 100 ]; then
		pushLinkStartLine=$( cat ${appTmp}/moc_report.reposumm.tmp | egrep -n "${repoName}-pushes-link" | head -1 | awk -F":" '{print $1}' )
		pushLinkEndLine=$( echo "${pushLinkStartLine} + 3" |bc )
		cat ${appTmp}/moc_report.reposumm.tmp | sed -e "${pushLinkStartLine}","${pushLinkEndLine}"d | sed -e '2,10d'       >>${appTmp}/moc_report.html
	fi

done
	
echo "</table>"	>>${appTmp}/moc_report.html

echo "
</body>
</html>
"	>>${appTmp}/moc_report.html


cp -p ${appTmp}/moc_report.html ${appOut}/moc_report.${reportGenDate}.html

echo ""
echo "SUBJECT: ${RPT_SUBJ}"
echo "BODY: ${RPT_BODY}"
echo ""

# send email for being non compliant
email_report_func


