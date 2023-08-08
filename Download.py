import os
import time
import urllib
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

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
dir = os.path.dirname(os.path.realpath(__file__))
user_token = ""
ReleaseType = "retail"
UpdateID = "00000000-0000-0000-0000-000000000000"
Version = "0.0.0.0"
ReleaseType_list = ["retail", "RP", "WIS", "WIF"]
RevisionNumber = 1
session = Session()
session.verify = False
print(dir)
try:
    response = urllib.request.urlopen("https://raw.githubusercontent.com/bubbles-wow/MS-Account-Token/main/token.cfg")
    text = response.read().decode("utf-8")
    user_token = Prop(text).get("user_code")
    updatetime = Prop(text).get("update_time")
    print("Successfully get user token from server!")
    print(f"Last update time: {updatetime}\n")
except:
    print("Notice: You haven't logged in yet. Some UpdateID may not be available.")
    time.sleep(1)
try:
    response = urllib.request.urlopen("https://raw.githubusercontent.com/bubbles-wow/WSA-Archive/main/UpdateID.cfg")
    text = response.read().decode("utf-8")
    Version = Prop(text).get("Version")
    UpdateID = Prop(text).get("UpdateID")
    print(f"Version: {Version}\n")
except:
    print("Cannot get UpdateID from server! Please check your network and try again.")
    exit()
Filename = "MicrosoftCorporationII.WindowsSubsystemForAndroid_" + Version + "_neutral_~_8wekyb3d8bbwe.Msixbundle"
print(Filename)
with open("FE3FileUrl.xml", "r") as f:
    FE3_file_content = f.read()
    f.close()
try:
    out = session.post(
        'https://fe3.delivery.mp.microsoft.com/ClientWebService/client.asmx/secured',
        data=FE3_file_content.format(user_token, UpdateID, RevisionNumber, ReleaseType),
        headers={'Content-Type': 'application/soap+xml; charset=utf-8'}
    )
except:
    print(f"\rNetwork Error! Please check your network and try again.",end="")
    time.sleep(1)
    exit()
doc = minidom.parseString(out.text)
if len(out.text) < 1500:
    print("Not found!")
    exit()
url = ""
for l in doc.getElementsByTagName("FileLocation"):
    url = l.getElementsByTagName("Url")[0].firstChild.nodeValue
    if url.split("/")[2] == "tlu.dl.delivery.mp.microsoft.com":
        print(f"File name: {Filename}")
        print(f"Download URL: {url}")
        break

os.makedirs(dir + "/output", exist_ok=True)
dir = dir + "/output"
response = requests.get(url)
with open(dir + "/" + Filename, "wb") as f:
    f.write(response.content)
    f.close()
if os.path.exists(dir + "/" + Filename):
    print("Successfully downloaded!")

