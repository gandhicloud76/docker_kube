#!/usr/bin/python3

from botocore.vendored import requests
import json
import ipaddress
import boto3
import json
import os
import requests
print(requests.__version__)


def main():

    # get service name as parameter
    #service_name = event["aws_service_name"]
    global service_name
    service_name = 'ycpi-test'
    
    # get ips to update IPSet for the service
    print('start')
    addresses, addresses_v2_ipv4, addresses_v2_ipv6 = get_service_ips()

    # get the ipset id for service IPSet    
    ipset_list = get_service_ipset()
    
    responses = []
    for ipset in ipset_list:
        # update IPSet for the service
        responses.append(update_ipset(ipset, addresses, addresses_v2_ipv4, addresses_v2_ipv6))
    
    return {
        "statusCode": 200,
        "statusDescription": "200 OK",
        "isBase64Encoded": False,
        "headers": {
            "Content-Type": "application/json"
        },
        "body": json.dumps(
            {"response": responses}
        )
    }

def get_service_ipset():
    
    #runtime_region = os.environ['AWS_REGION']
    runtime_region = 'us-east-1'
    client = boto3.client('wafv2', region_name=runtime_region)
    rsp = client.list_ip_sets(Scope='REGIONAL',Limit=100)
    
    service_ipset = []
    
    for line in rsp['IPSets']:
        if line["Name"] == service_name.lower():
            service_ipset.append(runtime_region + ':' + line["Id"])
    
    if len(service_ipset) == 0:
        print('Error: IPSet for the service not present')
    else:
        print('This Lambda Function would update ipset: ', service_ipset)
    
    return service_ipset
    
def get_service_ips():
    
    addresses = []
    addresses_v2_ipv4 = []
    addresses_v2_ipv6 = []
    
    s3client = boto3.client('s3',region_name='us-east-1')
 
    s3obj_ipv4 = s3client.get_object(Bucket='ycpi-ipset',Key='ipv4/ycpi.subnet.ipv4') 
    contents_ipv4 = s3obj_ipv4['Body'].read().decode('utf-8')
    
    for item in contents_ipv4.split("\n"):
        if item != '':
            addresses.append(item)
            addresses_v2_ipv4.append(item)
    
    s3obj_ipv6 = s3client.get_object(Bucket='ycpi-ipset',Key='ipv6/ycpi.subnet.ipv6') 
    contents_ipv6 = s3obj_ipv6['Body'].read().decode('utf-8')
    
    for item in contents_ipv6.split("\n"):
        if item != '':
            addresses_v2_ipv6.append(item)
    
    return addresses, addresses_v2_ipv4, addresses_v2_ipv6
    
def update_ipset(ipset, addresses, addresses_v2_ipv4, addresses_v2_ipv6):
    # Check for v2 first
    v2 = False
    if ':' in ipset:
        (region, ipset_id) = ipset.split(':', 2)
        client = boto3.client('wafv2', region_name=region)
    else:
        ipset_id = ipset
        client = boto3.client('wafv2')

    for scope in ['REGIONAL', 'CLOUDFRONT']:
        if scope == 'CLOUDFRONT':
            client = boto3.client('wafv2', region_name='us-east-1')

        rsp = client.list_ip_sets(Scope=scope)
        for item in rsp['IPSets']:
            if item['Id'] == ipset_id:
                v2 = True
                ipset_scope = scope
                ipset_name = item['Name']
                ipset_lock = item['LockToken']
                break
        if v2:
            break

    if v2:
        rsp = client.get_ip_set(Name=ipset_name, Scope=ipset_scope, Id=ipset_id)
    else:
        # See if we can find something for v1
        if ':' in ipset:
            (region, ipset_id) = ipset.split(':', 2)
            client = boto3.client('waf-regional', region_name=region)
        else:
            ipset_id = ipset
            client = boto3.client('waf-regional')

        try:
            rsp = client.get_ip_set(IPSetId=ipset_id)
        except:
            client = boto3.client('waf', region_name='us-east-1')
            try:
                rsp = client.get_ip_set(IPSetId=ipset_id)
            except:
                raise ValueError("Unable to locate ipset {0} in WAF v1 or v2, regional or global configurations".format(ipset))

    existing = []

    # Amazon returns IPV6 addresses in an unusual format.  Reparse for comparison
    if v2:
        for address in rsp['IPSet']['Addresses']:
            existing.append(str(ipaddress.ip_network(address)))
    else:
        for descr in rsp['IPSet']['IPSetDescriptors']:
            existing.append(str(ipaddress.ip_network(descr['Value'])))

    # v2 IPSets can only have V4 or V6 addresses
    if v2:
        if rsp['IPSet']['IPAddressVersion'] == 'IPV4':
            a = set(addresses_v2_ipv4)
        else:
            a = set(addresses_v2_ipv6)
    else:
        a = set(addresses)

    e = set(existing)
    adds = list(a - e)
    dels = list(e - a)
    keep = list(a & e)

    if v2:
        client.update_ip_set(Name=ipset_name, Scope=ipset_scope, Id=ipset_id, Addresses=list(a), LockToken=ipset_lock)

    else:
        token = client.get_change_token()['ChangeToken']
        updates = []
        for address in adds:
            if len(updates) == 100:
                response = client.update_ip_set(IPSetId=ipset_id, ChangeToken=token, Updates=updates)
                token = client.get_change_token()['ChangeToken']
                updates = []
            type = 'IPV6' if ':' in address else 'IPV4'
            updates.append({
                "Action": "INSERT",
                "IPSetDescriptor": { "Type": type, "Value": address }
            })

        for address in dels:
            if len(updates) == 100:
                response = client.update_ip_set(IPSetId=ipset_id, ChangeToken=token, Updates=updates)
                token = client.get_change_token()['ChangeToken']
                updates = []
            type = 'IPV6' if ':' in address else 'IPV4'
            updates.append({
                "Action": "DELETE",
                "IPSetDescriptor": { "Type": type, "Value": address }
            })

        if len(updates) > 0:
            response = client.update_ip_set(IPSetId=ipset_id, ChangeToken=token, Updates=updates)

    return {
        "IPSet": ipset_id,
        "Unmodified": len(keep),
        "Additions": len(adds),
        "Deletions": len(dels)
    }


main ()
