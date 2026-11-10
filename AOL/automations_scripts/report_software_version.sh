#!/usr/bin/sh 
java_version=$( java -version 2>&1 | head -1 | cut -d'"' -f2 )
aws_version=$( aws --version | cut -d' ' -f1 | cut -d'/' -f2 )
maven_version=$( mvn -v 2>&1 | head -1 | cut -d' ' -f3 )
gsutil_version=$( gsutil --v | cut -d' ' -f3 )
docker_version=$( docker -v | cut -d' ' -f3 | sed "s/,//g" )
terraform_version=$( terraform -v 2>&1 | head -1 | cut -d'v' -f2 )
node_version=$( node -v | cut -d'v' -f2 )
npm_version=$( npm -v )
newrelic_version=$( newrelic-infra --version | awk -F':' '{print $2}' | sed "s/ //g" | awk -F',' '{print $1}' )
trivy_version=$( trivy -v | cut -d' ' -f2 )
jq_version=$( jq --version | cut -d'-' -f2 )
calypso_version=$( calypso -yversion  | cut -d' ' -f2 | cut -d',' -f1 )
cameo_version=$( cameo -version | cut -d' ' -f2 | cut -d',' -f1 )
python_version=$( python --version 2>&1 | awk -F' ' '{print $2}')
echo "<table border='1'>
<tr>
  <th>Software</th>
  <th>Command</th>
  <th>Version</th>
</tr>
<tr>
  <td>java</td>
  <td>java -version</td>
  <td>${java_version}</td>
</tr>
<tr>
  <td>awscli</td>
  <td>aws --version</td>
  <td>${aws_version}</td>
</tr>
<tr>
  <td>maven</td>
  <td>mvn -v</td>
  <td>${maven_version}</td>
</tr>
<tr>
  <td>gsutil</td>
  <td>gsutil --v</td>
  <td>${gsutil_version}</td>
</tr>
<tr>
  <td>docker</td>
  <td>docker -v</td>
  <td>${docker_version}</td>
</tr>
<tr>
  <td>terraform</td>
  <td>terraform -v</td>
  <td>${terraform_version}</td>
</tr>
<tr>
  <td>node</td>
  <td>node -v</td>
  <td>${node_version}</td>
</tr>
<tr>
  <td>npm</td>
  <td>npm -v</td>
  <td>${npm_version}</td>
</tr>
<tr>
  <td>newrelic</td>
  <td>newrelic-infra --version</td>
  <td>${newrelic_version}</td>
</tr>
<tr>
  <td>trivy</td>
  <td>trivy -v</td>
  <td>${trivy_version}</td>
</tr>
<tr>
  <td>jq</td>
  <td>jq --version</td>
  <td>${jq_version}</td>
</tr>
<tr>
  <td>calypso</td>
  <td>calypso -yversion</td>
  <td>${calypso_version}</td>
</tr>
<tr>
  <td>cameo</td>
  <td>cameo -version</td>
  <td>${cameo_version}</td>
</tr>
<tr>
  <td>python</td>
  <td>python -V</td>
  <td>${python_version}</td>
</tr>
</table>" > output.html
