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

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
dir = os.path.dirname(os.path.realpath(__file__))
user_token = ""
ReleaseType = "retail"
UpdateID = "00000000-0000-0000-0000-000000000000"
Version = "0.0.0.0"
url = ""
ReleaseType_list = ["retail", "RP", "WIS", "WIF"]
RevisionNumber = 1
session = Session()
session.verify = False
if len(sys.argv) > 1:
    url = sys.argv[1]
if len(sys.argv) > 2:
    Version = sys.argv[2]
if len(sys.argv) < 2:
    try:
        response = requests.get("https://api.github.com/repos/bubbles-wow/WSAUpdateChecker/contents/UpdateInfo.cfg")
        if response.status_code == 200:
            content = response.json()["content"]
            content = content.encode("utf-8")
            content = base64.b64decode(content)
            text = content.decode("utf-8")
            Version = Prop(text).get("Version")
            url = Prop(text).get("URL")
        else:
            print("No availavle URL!")
            exit()
    except:
        print("No availavle URL!")
        exit()
if url == "":
    print("No availavle URL!")
    exit()
Filename = "MicrosoftCorporationII.WindowsSubsystemForAndroid_" + Version + "_neutral_~_8wekyb3d8bbwe.Msixbundle"
print(f"File name: {Filename}")
print(f"Download URL: {url}")
os.makedirs(dir + "/output", exist_ok=True)
dir = dir + "/output"
response = requests.get(url)
with open(dir + "/" + Filename, "wb") as f:
    f.write(response.content)
    f.close()
if os.path.exists(dir + "/" + Filename):
    print("Successfully downloaded!")
