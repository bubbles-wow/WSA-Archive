import os
import sys
import time
import base64
import urllib3
import requests

from typing import Any, OrderedDict
from xml.dom import minidom
from requests import Session

class Prop(OrderedDict):
    def __init__(self, props: str = ...) -> None:
        super().__init__()
        for i, line in enumerate(props.splitlines(False)):
            if '=' in line:
                k, v = line.split('=', 1)
                self[k] = v
            else:
                self[f".{i}"] = line

    def __setattr__(self, __name: str, __value: Any) -> None:
        self[__name] = __value

    def __repr__(self):
        return '\n'.join(f'{item}={self[item]}' for item in self)

FE3FileUrl = """<s:Envelope xmlns:a="http://www.w3.org/2005/08/addressing"
	xmlns:s="http://www.w3.org/2003/05/soap-envelope">
	<s:Header>
		<a:Action s:mustUnderstand="1">http://www.microsoft.com/SoftwareDistribution/Server/ClientWebService/GetExtendedUpdateInfo2</a:Action>
		<a:MessageID>urn:uuid:2cc99c2e-3b3e-4fb1-9e31-0cd30e6f43a0</a:MessageID>
		<a:To s:mustUnderstand="1">https://fe3.delivery.mp.microsoft.com/ClientWebService/client.asmx/secured</a:To>
		<o:Security s:mustUnderstand="1"
			xmlns:o="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd">
			<Timestamp xmlns="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">
				<Created>2017-08-01T00:29:01.868Z</Created>
				<Expires>2017-08-01T00:34:01.868Z</Expires>
			</Timestamp>
			<wuws:WindowsUpdateTicketsToken wsu:id="ClientMSA"
				xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd"
				xmlns:wuws="http://schemas.microsoft.com/msus/2014/10/WindowsUpdateAuthorization">
				<TicketType Name="MSA" Version="1.0" Policy="MBI_SSL">
					<user>{}</user>
				</TicketType>
			</wuws:WindowsUpdateTicketsToken>
		</o:Security>
	</s:Header>
	<s:Body>
		<GetExtendedUpdateInfo2 xmlns="http://www.microsoft.com/SoftwareDistribution/Server/ClientWebService">
			<updateIDs>
				<UpdateIdentity>
					<UpdateID>{}</UpdateID>
					<RevisionNumber>{}</RevisionNumber>
				</UpdateIdentity>
			</updateIDs>
			<infoTypes>
				<XmlUpdateFragmentType>FileUrl</XmlUpdateFragmentType>
				<XmlUpdateFragmentType>FileDecryption</XmlUpdateFragmentType>
			</infoTypes>
			<deviceAttributes>BranchReadinessLevel=CB;CurrentBranch=rs_prerelease;OEMModel=Virtual Machine;FlightRing={};AttrDataVer=21;SystemManufacturer=Microsoft Corporation;InstallLanguage=en-US;OSUILocale=en-US;InstallationType=Client;FlightingBranchName=external;FirmwareVersion=Hyper-V UEFI Release v2.5;SystemProductName=Virtual Machine;OSSkuId=48;FlightContent=Branch;App=WU;OEMName_Uncleaned=Microsoft Corporation;AppVer=10.0.22621.900;OSArchitecture=AMD64;SystemSKU=None;UpdateManagementGroup=2;IsFlightingEnabled=1;IsDeviceRetailDemo=0;TelemetryLevel=3;OSVersion=10.0.22621.900;DeviceFamily=Windows.Desktop;</deviceAttributes>
		</GetExtendedUpdateInfo2>
	</s:Body>
</s:Envelope>
"""

def GetURL(UpdateID):
    global FE3FileUrl
    session = Session()
    session.verify = False
    while True:
        try:
            response = requests.get("https://api.github.com/repos/bubbles-wow/MS-Account-Token/contents/token.cfg")
            while response.status_code != 200:
                print("Failed to get user code from github! Retrying...")
                continue
            content = response.json()["content"]
            content = content.encode("utf-8")
            content = base64.b64decode(content)
            text = content.decode("utf-8")
            user_token = Prop(text).get("user_code")
            out = session.post(
                'https://fe3.delivery.mp.microsoft.com/ClientWebService/client.asmx/secured',
                data=FE3FileUrl.format(user_token, UpdateID, 1, "WIF"),
                headers={'Content-Type': 'application/soap+xml; charset=utf-8'}
            )
            doc = minidom.parseString(out.text)
            if len(out.text) < 1500:
                print("Invaild UpdateID!")
                return ""
            for l in doc.getElementsByTagName("FileLocation"):
                url = l.getElementsByTagName("Url")[0].firstChild.nodeValue
                if url.split("/")[2] == "tlu.dl.delivery.mp.microsoft.com":
                    return url
        except:
            print("Failed to fetch URL! Retrying...")
            continue

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

UpdateID = ""
Version = ""
url = ""
Filename = ""

with open("UpdateInfo.cfg", "r") as f:
    text = f.read()
    Version = Prop(text).get("Version")
    UpdateID = Prop(text).get("UpdateID")
    url = Prop(text).get("URL")
    f.close()

if url == "":
    print("No availavle URL! Try to download by UpdateID from Microsoft Store.")
    if UpdateID == "":
        print("No UpdateID! Stop downloading.")
    else:
        url = GetURL(UpdateID)
        response = requests.get(url, stream=True)
        if response.status_code != 200:
            print("Failed to get URL! Retrying...")
        else:
            Filename = response.headers["Content-Disposition"].split(";")[1].split("=")[1].replace('"', '')
            Version = Filename.split("_")[1]
        if url == "":
            print("Failed to get URL! Stop downloading.")
            exit()
        else:
            print(f"Successfully get URL!")
else:
    if Version == "":
        print("No availavle Version!")
        exit()

if Filename == "":
    Filename = f"MicrosoftCorporationII.WindowsSubsystemForAndroid_{Version}_neutral_~_8wekyb3d8bbwe.Msixbundle"
os.environ["Version"] = Version
os.environ["Filename"] = Filename

print(f"File name: {Filename}")
print(f"Download URL: {url}")

dir = os.path.join(os.path.dirname(os.path.realpath(__file__)), "download")
os.makedirs(dir, exist_ok=True)

response = requests.get(url, stream=True)
if response.status_code != 200:
    print("Failed to get URL! Stop downloading.")
    exit()
with open(os.path.join(dir, Filename), "wb") as f:
    for chunk in response.iter_content(chunk_size=1024):
        if chunk:
            f.write(chunk)
    f.close()

if os.path.exists(os.path.join(dir, Filename)):
    print("Successfully downloaded!")
