import boto3
import requests
from requests_aws4auth import AWS4Auth

host = 'https://vpc-obi-qat-elasticsearch-bmndk5oqylrbqklxtsrkc5u4iy.us-east-1.es.amazonaws.com/'
region = 'us-east-1'
service = 'es'
credentials = boto3.Session().get_credentials()
awsauth = AWS4Auth(credentials.access_key, credentials.secret_key, region, service, session_token=credentials.token)

path ='_opendistro/_security/api/rolesmapping/all_access' # the OpenSearch API endpoint
url = host+path

headers = {"Content-Type": "application/json"}

r = requests.get(url, auth=awsauth, headers=headers)

print(r.status_code)
print(r.text)
