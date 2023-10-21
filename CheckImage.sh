#!/bin/bash

abort() {
    [ "$1" ] && echo -e "ERROR: $1"
    echo "CheckImage: an error has occurred, exit"
    exit 1
}

ro_ext4_img_to_rw() {
    resize_img "$1" "$(($(du --apparent-size -sB512 "$1" | cut -f1) * 2))"s || return 1
    e2fsck -fp -E unshare_blocks "$1" || return 1
    resize_img "$1" || return 1
    return 0
}

resize_img() {
    sudo e2fsck -pf "$1" || return 1
    if [ "$2" ]; then
        sudo resize2fs "$1" "$2" || return 1
    else
        sudo resize2fs -M "$1" || return 1
    fi
    return 0
}

cd ./download
FileName=$(ls *.Msixbundle) || abort
PackageVersion=$(echo $FileName | cut -d'_' -f2) || abort
mv $FileName wsa.zip || abort
unzip wsa.zip "WsaPackage_${PackageVersion}_x64_Release-Nightly.msix" || abort
rm -rf wsa.zip || abort
mv "WsaPackage_${PackageVersion}_x64_Release-Nightly.msix" wsa.zip || abort
if [ "PackageVersion" \< "2302" ]; then
    unzip wsa.zip system.img product.img || abort
else
    unzip wsa.zip system.vhdx product.vhdx || abort
    qemu-img convert -q -f vhdx -O raw system.vhdx system.img || abort
    qemu-img convert -q -f vhdx -O raw product.vhdx product.img || abort
    rm -rf system.vhdx product.vhdx || abort
fi
unzip wsa.zip Tools/kernel || abort
mv ./Tools/kernel ./kernel || abort
rm -rf wsa.zip ./Tools || abort

mkdir -p ./system || abort
mkdir -p ./product || abort
ImageType=$(blkid -o value -s TYPE system.img) || abort
if [ "$ImageType" == "ext4" ]; then
    ro_ext4_img_to_rw system.img > /dev/null || abort
    ro_ext4_img_to_rw product.img > /dev/null || abort
    sudo mount -o loop system.img ./system || abort
    sudo mount -o loop product.img ./product || abort
elif [ "$ImageType" == "erofs" ]; then
    sudo mount -t erofs system.img ./system || abort
    sudo mount -t erofs product.img ./product || abort
else
    abort "system image is not supported"
fi

BuildProp=$(sudo cat ./system/system/build.prop)
AndroidVersion=$(echo "$BuildProp" | sed -n 's/^ro.build.version.release=//p')
API=$(echo "$BuildProp" | sed -n 's/^ro.build.version.sdk=//p')
SeculityPatch=$(echo "$BuildProp" | sed -n 's/^ro.build.version.security_patch=//p')
BuildID=$(echo "$BuildProp" | sed -n 's/^ro.build.id=//p')

KernelInfo=$(file kernel | awk -F ', ' '{print $2}' | sed 's/version //; s/(\(.*\)) //')
KernelMain=$(echo $KernelInfo | cut -d'-' -f1)

WebViewVersion=$(sudo aapt dump badging ./product/app/webview/webview.apk | grep -oP "versionName='\K[^']+")

if [ "$API" == "32" ]; then
    AndroidVersion="12L"
    AndroidInfoURL="https://developer.android.google.cn/about/versions/12/12L"
else
    AndroidInfoURL="https://developer.android.google.cn/about/versions/$AndroidVersion"
fi

SecPatchURL="https://source.android.com/security/bulletin/${SeculityPatch:0:9}1"
SecPatchHead=$(curl -s -L $SecPatchURL | grep -oP '<title>\K[^<]+' | sed 's/&nbsp;//g')
SecPatchDate=$(echo $SecPatchHead | grep -oP '\b[A-Z][a-z]+ \d{4}\b')

echo "PackageVersion: $PackageVersion"
echo "AndroidVersion: $AndroidVersion"
echo "API: $API"
echo "SeculityPatch: $SeculityPatch"
echo "Kernel: $KernelInfo"
echo "BuildID: $BuildID"
echo "WebViewVersion: $WebViewVersion"

Description="
## Details
  - [Android $AndroidVersion]($AndroidInfoURL) | API $API
  - Seculity patch
    \`\`\`
    $SeculityPatch
    \`\`\`
    Note: [Android Security Bulletin—**$SecPatchDate** | Android Open Source Project]($SecPatchURL)
  - Kernel Version
    \`\`\`
    $KernelInfo
    \`\`\`
    Source: [latte-2/**$KernelMain**](https://github.com/microsoft/WSA-Linux-Kernel/)
  - Build ID: 
    \`\`\`
    $BuildID
    \`\`\`
  - Chromium WebView Version: \`$WebViewVersion\`"

touch INFO.md || abort
sudo echo "$Description" > INFO.md || abort

sudo umount ./system || abort
sudo umount ./product || abort
rm -rf ./system ./product system.img product.img kernel || abort