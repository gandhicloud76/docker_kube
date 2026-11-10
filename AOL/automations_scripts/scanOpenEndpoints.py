#!/usr/bin/python3
__author__ = 'anildalli'
import argparse
import boto3.session
import boto3
import datetime
import json
import csv
import os
import socket
import sys
# to print set DEBUG = True, to NOT print set DEBUG = False
#
#DEBUG = True
DEBUG = False
# function to print message only if DEBUG = True
#
def printMsg(s):
        if DEBUG:
            print(s)
        return printMsg
# function to get Current time for printing
#
def getCurrTime():
    currTime = datetime.datetime.now()
    currTimeHRF = currTime.strftime("%Y-%m-%d %H:%M")
    
    return currTimeHRF
# function to source config file, declare and initialize variables 
#
def initProgram():
        printMsg('start : initProgram')
        global baseDir, appTmp, appOut
        global elbVar, elbVar2, ec2Var
        global elbJsonFile, elbCsvFile, elbv2JsonFile, elbv2CsvFile, elbAllCsvFile, elbsAllowed, elbInternetFacingCsvFile, elbInternalCsvFile
        global elbToScanEndPointsCsvFile, elbOpenCsvFile, elbNotOpenCsvFile
        global elb_dict, elbv2_dict, elb_item, elbv2_item
        global ec2JsonFile, ec2CsvFile, ec2AllCsvFile, ec2sAllowed, ec2PublicFacingCsvFile, ec2PublicFacingActiveCsvFile
        global ec2ToScanEndPointsCsvFile, ec2OpenCsvFile, ec2NotOpenCsvFile
        global ec2_dict
        global telnetResult, vpcID, openEndPointsAlarmFile 
        baseDir             		= '.'
        appTmp              		= baseDir + '/' + 'tmp'
        appOut              		= baseDir + '/' + 'output'
        elbsAllowed         		= os.environ["elbsAllowed"]
        elbVar              		= 'elb'
        elbVar2             		= elbVar + 'v2'
        elbJsonFile             	= appTmp + '/' + aws_acct_num + '.' + elbVar + '.json'
        elbCsvFile              	= appTmp + '/' + aws_acct_num + '.' + elbVar + '.csv'
        elbv2JsonFile           	= appTmp + '/' + aws_acct_num + '.' + elbVar2 + '.json'
        elbv2CsvFile            	= appTmp + '/' + aws_acct_num + '.' + elbVar2 + '.csv'
        elbAllCsvFile           	= appTmp + '/' + aws_acct_num + '.' + elbVar + '.all.csv'
        elbInternetFacingCsvFile    	= appTmp + '/' + aws_acct_num + '.' + elbVar + '.internet-facing.csv'
        elbInternalCsvFile      	= appTmp + '/' + aws_acct_num + '.' + elbVar + '.internal.csv'
        elbToScanEndPointsCsvFile       = appTmp + '/' + aws_acct_num + '.' + elbVar + '.to-scan-end-points.csv'
        elbOpenCsvFile          	= appTmp + '/' + aws_acct_num + '.' + elbVar + '.open.csv'
        elbNotOpenCsvFile       	= appTmp + '/' + aws_acct_num + '.' + elbVar + '.not-open.csv'
        ec2sAllowed         		= os.environ["ec2sAllowed"]
        ec2Var              		= 'ec2'
        ec2JsonFile             	= appTmp + '/' + aws_acct_num + '.' + ec2Var + '.json'
        ec2CsvFile              	= appTmp + '/' + aws_acct_num + '.' + ec2Var + '.csv'
        ec2AllCsvFile           	= appTmp + '/' + aws_acct_num + '.' + ec2Var + '.all.csv'
        ec2PublicFacingCsvFile          = appTmp + '/' + aws_acct_num + '.' + ec2Var + '.public-facing.csv'
        ec2PublicFacingActiveCsvFile    = appTmp + '/' + aws_acct_num + '.' + ec2Var + '.public-facing-active.csv'
        ec2ToScanEndPointsCsvFile       = appTmp + '/' + aws_acct_num + '.' + ec2Var + '.to-scan-end-points.csv'
        ec2OpenCsvFile          	= appTmp + '/' + aws_acct_num + '.' + ec2Var + '.open.csv'
        ec2NotOpenCsvFile       	= appTmp + '/' + aws_acct_num + '.' + ec2Var + '.not-open.csv'
        openEndPointsAlarmFile      	= appOut + '/' + 'Open_Public_Facing_End_Points.csv'
        if not os.path.exists(appTmp):
            os.mkdir(appTmp)
        if not os.path.exists(appOut):
            os.mkdir(appOut)
        printMsg('end   : initProgram')
        return initProgram
# function to get AWS account number 
#
def getAWSAcctNum():
    printMsg('start : getAWSAcctNum')
    global aws_acct_num
    acct_cd = boto3.client('sts')
    acct_dic = acct_cd.get_caller_identity()
    aws_acct_num = acct_dic["Account"]
    print('AWS AC: '+ aws_acct_num)
    printMsg('end   : getAWSAcctNum')
    return getAWSAcctNum
# function to decribe load balancer i.e. elb (classic) using boto3 library
#
def getELBinfo():
        printMsg('start : getELBinfo')
        
        elb_cd = boto3.client('elb','us-east-1')
        elb_marker = None
        elb_item = 'LoadBalancerDescriptions'
        while True:
            if elb_marker:
                elb_kwargs = {'Marker': elb_marker}
            else:
                elb_kwargs = {}
        
                elb_dict = elb_cd.describe_load_balancers(**elb_kwargs)
            try:    
                        elb_marker = elb_dict.get('NextMarker')
            except KeyError:
                        printMsg('Info  : ELB NextMarker Key does not exist')
            if not elb_marker:
                break
        writeJSONdata(elb_dict,elbJsonFile)
        writeELBSelectCSVdata(elbCsvFile,elb_dict,elb_item)
        printMsg('end   : getELBinfo')
        return getELBinfo
# function to describe load balancer i.e. elbv2 (network and application) using boto3 library
#
def getELBv2info():
    printMsg('start : getELBv2info')  
    elbv2_cd = boto3.client('elbv2', 'us-east-1')
    elbv2_marker = None
    elbv2_item = 'LoadBalancers'
    while True:
        if elbv2_marker:
            elbv2_kwargs = {'Marker': elbv2_marker}
        else:
            elbv2_kwargs = {}
        elbv2_dict = elbv2_cd.describe_load_balancers(**elbv2_kwargs)
        try:    
                        elbv2_marker = elbv2_dict.get('NextMarker')
        except KeyError:
                        printMsg('Info  : ELBv2 NextMarker Key does not exist')
        if not elbv2_marker:
            break
    writeJSONdata(elbv2_dict,elbv2JsonFile)
    writeELBSelectCSVdata(elbv2CsvFile,elbv2_dict,elbv2_item)
    printMsg('end   : getELBv2info')
    return getELBv2info
# function to write formatted JSON data
#
def writeJSONdata(dictName,jsonFileName):
    printMsg('start : writeJSONdata')
    with open(jsonFileName, 'w+') as fileOut:
                fileOut.write(json.dumps(dictName, indent=4, sort_keys=True, default=str))
                fileOut.close()
    printMsg('end   : writeJSONdata')
    return writeJSONdata
# function to get values of selective fields from ELB JSON data 
#
def listInfoELB(dictName,itemName):
        infoIWant = []   #list with empty parameters
        for myList in dictName[itemName]:
                tempInfo = []
                try:
                        tempInfo.append(myList["Type"])
                except KeyError:
                        tempInfo.append("classic")
                tempInfo.append(myList["LoadBalancerName"])
                tempInfo.append(myList["Scheme"])
                tempInfo.append(myList["DNSName"])
                try:
                        tempSubInfoLD = []
                        for mySubListLD in myList["ListenerDescriptions"]:
                                tempSubInfoLD.append(mySubListLD["Listener"]["LoadBalancerPort"])
                        tempSubInfoLDListToStr = ':'.join(map(str,tempSubInfoLD))
                except KeyError:
                        tempSubInfoLDListToStr = ''
                try:
                        tempSubInfoFP = []
                        lbARN = myList["LoadBalancerArn"]
                        tempSubInfoFPListToStr = getFwdListenerPort(lbARN)
                except KeyError:
                        tempSubInfoFPListToStr = ''
                allInputPorts = tempSubInfoLDListToStr + ":" + tempSubInfoFPListToStr
                allInputPortsList = allInputPorts.split(':')
                allInputPortsListUniq = list(set(allInputPortsList))
                allInputPortsListUniqToStr = ':'.join(map(str,allInputPortsListUniq))
                allInputPortsListUniqToStrFmt = allInputPortsListUniqToStr.lstrip(':').rstrip(':').replace('::',':')
                tempInfo.append(allInputPortsListUniqToStrFmt)
                infoIWant.append(tempInfo)
        return infoIWant
# function to get forwarding lister ports
#
def getFwdListenerPort(lb_arn):
        elbv2_ld_cd = boto3.client('elbv2','us-east-1')
        ld = elbv2_ld_cd.describe_listeners(LoadBalancerArn=lb_arn)
        tempSubInfoLP = []
        for x in ld["Listeners"]:
                for y in x["DefaultActions"]:
                        defActionType = y["Type"]
                        if [ defActionType == 'forward' ]:
                                fwdPort = x["Port"]
                                tempSubInfoLP.append(fwdPort)
        tempSubInfoLPtoStr = ':'.join(map(str,tempSubInfoLP))
        fwdLPList = tempSubInfoLPtoStr.split(':')
        fwdLPListUniq = list(set(fwdLPList))
        fwdLPListUniqToStr = ':'.join(map(str,fwdLPListUniq))
        fwdLPListUniqToStrFmt = fwdLPListUniqToStr.lstrip(':').rstrip(':').replace('::',':')
        return fwdLPListUniqToStrFmt
# function to write select fields from ELB data to CSV
#
def writeELBSelectCSVdata(csvFileName,dictName,itemName):
    printMsg('start : writeELBSelectCSVdata')
    with open(csvFileName, 'w+') as csvFileOut:
                wr = csv.writer(csvFileOut, quoting=csv.QUOTE_ALL)
                for row in listInfoELB(dictName,itemName):
                        wr.writerow([w.encode('utf-8').decode('utf-8') for w in row])
                csvFileOut.close()
    
    printMsg('end   : writeELBSelectCSVdata')
    return writeELBSelectCSVdata
# function to filter internet facing ELBs
#
def getInternetFacingELBs():
    printMsg('start : getInternetFacingELBs')
    #concatenate classic, application, network elbs
    if os.path.exists(elbCsvFile):
        with open(elbCsvFile,'r') as f_inp, open(elbAllCsvFile,'w') as f_out:
            for line in f_inp:
                f_out.write(line.replace('"', '').replace("'", ""))
        f_inp.close()
        f_out.close()
    else:
        printMsg("Error : File NOT found {}".format(elbCsvFile))
        sys.exit()
    if os.path.exists(elbv2CsvFile):
        with open(elbv2CsvFile,'r') as f_inp, open(elbAllCsvFile,'a') as f_out:
            for line in f_inp:
                f_out.write(line.replace('"', '').replace("'", ""))
        f_inp.close()
        f_out.close()
    else:
        printMsg("Error : File NOT found {}".format(elbv2CsvFile))
        sys.exit()
    #filter internet-facing and internal elbs from the total elbs
    with open(elbAllCsvFile,'r') as all_elbs_csv:
        reader = csv.reader(all_elbs_csv,delimiter=',')
        if_results = list(filter(lambda row: row[2] == 'internet-facing', reader))
    all_elbs_csv.close()
    with open(elbInternetFacingCsvFile,'w') as if_elbs_csv:
        writer = csv.writer(if_elbs_csv)
        for result in if_results:
            writer.writerow(result)
    if_elbs_csv.close()
    with open(elbAllCsvFile,'r') as all_elbs_csv:
        reader = csv.reader(all_elbs_csv,delimiter=',')
        in_results = list(filter(lambda row: row[2] == 'internal', reader))
    all_elbs_csv.close()
    with open(elbInternalCsvFile,'w') as in_elbs_csv:
        writer = csv.writer(in_elbs_csv)
        for result in in_results:
            writer.writerow(result)
    in_elbs_csv.close()
    printMsg('end   : getInternetFacingELBs')
    return getInternetFacingELBs
# function to identify Open ELBs
#
def identifyOpenELBs():
    printMsg('start : identifyOpenELBs')
    open(elbOpenCsvFile,'w').close()
    ifELBinp = csv.reader(open(elbInternetFacingCsvFile, 'r'), delimiter=',')    
    alarmPubELBout = csv.writer(open(elbToScanEndPointsCsvFile, 'w')) 
    for ifELB in ifELBinp:
        if ifELB[1] in elbsAllowed:
            continue
        else:
            alarmPubELBout.writerow(ifELB) 
            if ifELB[4]:
                for portNum in ifELB[4].split(':'):
                    doTelnetELB(ifELB[3],int(portNum),ifELB[0],ifELB[1],ifELB[2])
            else:
                printMsg("Info  : No port info for {} ({})".format(ifELB[1],ifELB[0]))
    printMsg('end   : identifyOpenELBs')
    return identifyOpenELBs
# function to do telnet/socket test to identify open end points
#
def doTelnetELB(dnsHostName,portNum,typeELB,nameELB,schemeELB):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2)
    of = open(elbOpenCsvFile,'a')
    nof = open(elbNotOpenCsvFile,'a')
    try :
                s.connect((dnsHostName,portNum))
    except :
                telnetResult = 'Not-Open,' + aws_acct_num + ',ELB(' + typeELB + '),' + nameELB + ',' + dnsHostName + ',' + str(portNum)
                nof.write(telnetResult)
                nof.write('\n')
                nof.close()
                return doTelnetELB
    telnetResult = 'Open,' + aws_acct_num + ',ELB(' + typeELB + '),' + nameELB + ',' + dnsHostName + ',' + str(portNum)
    of.write(telnetResult)
    of.write('\n')
    of.close()
    return doTelnetELB


# function to print info on ELBs
#
def printELBinfo():
    printMsg('start : printELBinfo')

    num_all_elbs=0
    num_classic_elbs=0
    num_application_elbs=0
    num_network_elbs=0
    num_if_elbs=0
    num_in_elbs=0
    num_nwif_elbs=0
    num_open_elbs=0
    with open(elbAllCsvFile) as f_inp_all:
        for line in f_inp_all:
            if line.strip():
                num_all_elbs += 1
    f_inp_all.close()
    allELBinp = csv.reader(open(elbAllCsvFile, 'r'), delimiter=',')
    for allELB in allELBinp:
        if allELB[0] == 'classic':
            num_classic_elbs += 1
        if allELB[0] == 'application':
            num_application_elbs += 1
        if allELB[0] == 'network':
            num_network_elbs += 1
    with open(elbInternetFacingCsvFile) as f_inp_if:
        for line in f_inp_if:
            if line.strip():
                num_if_elbs += 1
    f_inp_if.close()
    with open(elbInternalCsvFile) as f_inp_in:
        for line in f_inp_in:
            if line.strip():
                num_in_elbs += 1
    f_inp_in.close()
    with open(elbToScanEndPointsCsvFile) as f_inp_nwif:
        for line in f_inp_nwif:
            if line.strip():
                num_nwif_elbs += 1
    f_inp_nwif.close()
    with open(elbOpenCsvFile) as f_inp_open:
        for line in f_inp_open:
            if line.strip():
                num_open_elbs += 1
    f_inp_open.close()
    printMsg('+-------------------------------------------------')
    printMsg('+   AWS Account - ' + aws_acct_num )
    printMsg('+-------------------------------------------------')
    printMsg('+   ELBs (total)                           : ' + str(num_all_elbs))
    printMsg('+   ELBs (classic)                         : ' + str(num_classic_elbs))
    printMsg('+   ELBs (application)                     : ' + str(num_application_elbs))
    printMsg('+   ELBs (network)                         : ' + str(num_network_elbs))
    printMsg('+   ELBs (internet-facing)                 : ' + str(num_if_elbs))
    printMsg('+   ELBs (internal)                        : ' + str(num_in_elbs))
    printMsg('+   ELBs (for end points check)            : ' + str(num_nwif_elbs))
    printMsg('+   ELBs (open ports)                      : ' + str(num_open_elbs))
    printMsg('+-------------------------------------------------')
    openEP = open(openEndPointsAlarmFile,'a')
    with open(elbOpenCsvFile,"r") as f_inp_open:
        openELBs = csv.reader(f_inp_open,delimiter=',')
        for row in openELBs:
            openEPRow = row[0] + ' :AWS-Account=' + row[1] + ' :' + row[2] + ' :Name=' + row[3] + ' :DNSName=' + row[4] + ' :Port=' + row[5]
            openEP.write(openEPRow)
            openEP.write('\n')
            #printMsg(row[0] + ' :AWS-Account=' + row[1] + ' :' + row[2] + ' :Name=' + row[3] + ' :DNSName=' + row[4] + ' :Port=' + row[5])
            print(openEPRow)
    f_inp_open.close()
    openEP.close()

    printMsg('end   : printELBinfo')
    return printELBinfo


# function to describe instances i.e. ec2 using boto3 library
#
def getEC2info():
    printMsg('start : getEC2info')

    ec2_cd = boto3.client('ec2', 'us-east-1')
    ec2_next_token = None
    while True:
        if ec2_next_token:
            ec2_kwargs = {'Marker': ec2_next_token}
        else:
            ec2_kwargs = {}

        ec2_dict = ec2_cd.describe_instances(**ec2_kwargs)
        try:
            ec2_next_token = ec2_dict.get('NextToken')
        except KeyError:
            printMsg('Info  : EC2 NextToken Key does not exist')
        if not ec2_next_token:
            break
    writeJSONdata(ec2_dict,ec2JsonFile)
    writeEC2SelectCSVdata(ec2CsvFile,ec2_dict)

    printMsg('end   : getEC2info')
    return getEC2info


# function to get values of selective fields from EC2 JSON data
#
def listInfoEC2(dictName):
    infoIWant = []   #list with empty parameters
    for myListRes in dictName["Reservations"]:
        for myList in myListRes["Instances"]:
            tempInfo = []
            tempInfo.append(myList["InstanceId"])
            try:
                tempInfo.append(myList["State"]["Name"])
            except KeyError:
                tempInfo.append('NA-StateName')
            try:
                tempInfo.append(myList["PublicIpAddress"])
            except KeyError:
                tempInfo.append('NA-PubIPAdd')
            try:
                tempInfo.append(myList["VpcId"])
                vpcID = myList["VpcId"]
            except KeyError:
                tempInfo.append('NA-VpcId')
            try:
                tempSubInfoSG = []
                for mySubListSG in myList["SecurityGroups"]:
                    tempSubInfoSG.append(mySubListSG["GroupId"])
                tempSubInfoSGListToStr = ':'.join(map(str,tempSubInfoSG))
                tempInfo.append(tempSubInfoSGListToStr)
                tempSubInfoSGIP = []
                for sgID in tempSubInfoSG:
                    sgIP = getToPortSecGroup(sgID,vpcID)
                    tempSubInfoSGIP.append(sgIP)
                tempSubInfoSGIPListToStr = ':'.join(map(str,tempSubInfoSGIP))
            except KeyError:
                tempInfo.append('')
                tempSubInfoSGIPListToStr = ''
            allIngressPorts = tempSubInfoSGIPListToStr + ":"
            allIngressPortsList = allIngressPorts.split(':')
            allIngressPortsListUniq = list(set(allIngressPortsList))
            allIngressPortsListUniqToStr = ':'.join(map(str,allIngressPortsListUniq))
            allIngressPortsListUniqToStrFmt = allIngressPortsListUniqToStr.lstrip(':').rstrip(':').replace('::',':')
            tempInfo.append(allIngressPortsListUniqToStrFmt)
            infoIWant.append(tempInfo)

    return infoIWant


# function to get ToPort (ingress) configured in Security Group
#
def getToPortSecGroup(sgID,vpcID):
    ec2_cd = boto3.client('ec2','us-east-1')
    sg = ec2_cd.describe_security_groups(GroupIds=[sgID])
    tempSubInfoSSS = []
    for x in sg["SecurityGroups"]:
        for y in x["IpPermissions"]:
            try:
                tempSubInfoSSS.append(y["ToPort"])
            except KeyError:
                tempSubInfoSSS.append('')
        tempSubInfoSSSListToStr = ':'.join(map(str,tempSubInfoSSS))

    return tempSubInfoSSSListToStr


# function to write select fields from EC2 data to CSV
#
def writeEC2SelectCSVdata(csvFileName,dictName):
    printMsg('start : writeEC2SelectCSVdata')

    with open(csvFileName, 'w+') as csvFileOut:
        wr = csv.writer(csvFileOut, quoting=csv.QUOTE_ALL)
        for row in listInfoEC2(dictName):
            wr.writerow([w.encode('utf-8').decode('utf-8') for w in row])
        csvFileOut.close()

    printMsg('end   : writeEC2SelectCSVdata')
    return writeEC2SelectCSVdata


# function to get Public Facing IP address for running instances
#
def getPublicFacingActiveEC2s():
    printMsg('start : getPublicFacingActiveEC2s')

    if os.path.exists(ec2CsvFile):
        with open(ec2CsvFile,'r') as f_inp, open(ec2AllCsvFile,'w') as f_out:
            for line in f_inp:
                f_out.write(line.replace('"', '').replace("'", ""))
        f_inp.close()
        f_out.close()
    else:
        printMsg("Error : File NOT found {}".format(ec2CsvFile))
        sys.exit()
    with open(ec2AllCsvFile,'r') as all_ec2s_csv:
        reader = csv.reader(all_ec2s_csv,delimiter=',')
        if_results_pub = list(filter(lambda row: row[2] != 'NA-PubIPAdd', reader))
    all_ec2s_csv.close()
    with open(ec2PublicFacingCsvFile,'w') as if_pub_ec2s_csv:
        writer = csv.writer(if_pub_ec2s_csv)
        for result_pub in if_results_pub:
            writer.writerow(result_pub)
    if_pub_ec2s_csv.close()
    with open(ec2PublicFacingCsvFile,'r') as all_pub_ec2s_csv:
        reader = csv.reader(all_pub_ec2s_csv,delimiter=',')
        if_results_pub_active = list(filter(lambda row: row[1] != 'stopped', reader))
    all_pub_ec2s_csv.close()
    with open(ec2PublicFacingActiveCsvFile,'w') as if_pub_ec2s_active_csv:
        writer = csv.writer(if_pub_ec2s_active_csv)
        for result_pub_active in if_results_pub_active:
            writer.writerow(result_pub_active)
    if_pub_ec2s_active_csv.close()

    printMsg('end   : getPublicFacingActiveEC2s')
    return getPublicFacingActiveEC2s

# function to identify Open EC2s
#
def identifyOpenEC2s():
    printMsg('start : identifyOpenEC2s')

    open(ec2OpenCsvFile,'w').close()
    ifEC2inp = csv.reader(open(ec2PublicFacingActiveCsvFile, 'r'), delimiter=',')
    alarmPubEC2out = csv.writer(open(ec2ToScanEndPointsCsvFile, 'w'))
    for ifEC2 in ifEC2inp:
        if ifEC2[0] in ec2sAllowed:
            continue
        else:
            alarmPubEC2out.writerow(ifEC2)
            if ifEC2[5]:
                for portNum in ifEC2[5].split(':'):
                    doTelnetEC2(ifEC2[2],int(portNum),ifEC2[0],ifEC2[1])
            else:
                printMsg("Info  : No port info for {} ({})".format(ifEC2[1],ifEC2[0]))

    printMsg('end   : identifyOpenEC2s')
    return identifyOpenEC2s


# function to do telnet/socket test to identify open end points
#
def doTelnetEC2(pubIPaddress,portNum,instanceID,instanceState):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2)
    of = open(ec2OpenCsvFile,'a')
    nof = open(ec2NotOpenCsvFile,'a')
    try :
        s.connect((pubIPaddress,portNum))
    except :
        telnetResult = 'Not-Open,' + aws_acct_num + ',EC2(' + instanceState + '),' + instanceID + ',' + pubIPaddress + ',' + str(portNum)
        nof.write(telnetResult)
        nof.write('\n')
        nof.close()
        return doTelnetEC2
    telnetResult = 'Open,' + aws_acct_num + ',EC2(' + instanceState + '),' + instanceID + ',' + pubIPaddress + ',' + str(portNum)
    of.write(telnetResult)
    of.write('\n')
    of.close()
    return doTelnetEC2

# function to print info on Public facing EC2s
#
def printEC2info():
    printMsg('start : printEC2info')

    num_all_ec2s=0
    num_pf_ec2s=0
    num_pf_ru_ec2s=0
    num_nwpf_ec2s=0
    num_open_ec2s=0
    with open(ec2AllCsvFile) as f_inp_all:
        for line in f_inp_all:
            if line.strip():
                num_all_ec2s += 1
    f_inp_all.close()
    with open(ec2PublicFacingCsvFile) as f_inp_pf:
        for line in f_inp_pf:
            if line.strip():
                num_pf_ec2s += 1
    f_inp_pf.close()
    with open(ec2PublicFacingActiveCsvFile) as f_inp_pf_ru:
        for line in f_inp_pf_ru:
            if line.strip():
                num_pf_ru_ec2s += 1
    f_inp_pf_ru.close()
    with open(ec2ToScanEndPointsCsvFile) as f_inp_nwpf:
        for line in f_inp_nwpf:
            if line.strip():
                num_nwpf_ec2s += 1
    f_inp_nwpf.close()
    with open(ec2OpenCsvFile) as f_inp_open:
        for line in f_inp_open:
            if line.strip():
                num_open_ec2s += 1
    f_inp_open.close()
    printMsg('+-------------------------------------------------')
    printMsg('+   AWS Account - ' + aws_acct_num )
    printMsg('+-------------------------------------------------')
    printMsg('+   EC2s (total)                           : ' + str(num_all_ec2s))
    printMsg('+   EC2s (public-facing)                   : ' + str(num_pf_ec2s))
    printMsg('+   EC2s (public-facing-running)           : ' + str(num_pf_ru_ec2s))
    printMsg('+   EC2s (for end points check)            : ' + str(num_nwpf_ec2s))
    printMsg('+   EC2s (open ports)                      : ' + str(num_open_ec2s))
    printMsg('+-------------------------------------------------')
    openEP = open(openEndPointsAlarmFile,'a')
    with open(ec2OpenCsvFile,"r") as f_inp_open:
        openEC2s = csv.reader(f_inp_open,delimiter=',')
        for row in openEC2s:
            openEPRow = row[0] + ' :AWS-Account=' + row[1] + ' :' + row[2] + ' :InstanceID=' + row[3] + ' :PublicIP=' + row[4] + ' :Port=' + row[5]
            openEP.write(openEPRow)
            openEP.write('\n')
            #printMsg(row[0] + ' :AWS-Account=' + row[1] + ' :' + row[2] + ' :InstanceID=' + row[3] + ' :PublicIP=' + row[4] + ' :Port=' + row[5])
            print(openEPRow)
    f_inp_open.close()
    openEP.close()

    printMsg('end   : printEC2info')
    return printEC2info


# function main
#
def main():
    print('START : Scan open end points for ELBs and Public facing IPs : ' + getCurrTime())
    getAWSAcctNum()
    initProgram()
    getELBinfo()
    getELBv2info()
    getInternetFacingELBs()
    identifyOpenELBs()
    printELBinfo()
    getEC2info()
    getPublicFacingActiveEC2s()
    identifyOpenEC2s()
    printEC2info()
    print('END   : Scan open end points for ELBs and Public facing IPs : ' + getCurrTime())


# call main function - starting point
main()
