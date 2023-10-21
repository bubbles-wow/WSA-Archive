#!/bin/bash

abort() {
    [ "$1" ] && echo -e "ERROR: $1"
    echo "CheckImage: an error has occurred, exit"
    exit 1
}

fix_ext4_img() {
    sudo resize2fs "$1" "$(($(du --apparent-size -sB512 "$1" | cut -f1) * 2))"s > /dev/null || return 1
    sudo e2fsck -fp -E unshare_blocks "$1" > /dev/null || return 1
    sudo e2fsck -pf "$1" > /dev/null || return 1
    return 0
}

cd ./download
FileName=$(find -name "*.Msixbundle" | head -n 1) || abort
PackageVersion=$(echo $FileName | cut -d'_' -f2) || abort
MainVersion=$(echo $PackageVersion | cut -d'.' -f1) || abort
mv $FileName wsa.zip || abort
echo "Found package: $FileName"
echo ""

echo "Extract package..."
unzip wsa.zip "WsaPackage_${PackageVersion}_x64_Release-Nightly.msix" > /dev/null || abort
rm -rf wsa.zip || abort
mv "WsaPackage_${PackageVersion}_x64_Release-Nightly.msix" wsa.zip || abort
echo "Extract done!"
echo ""

echo "Extract image and kernel..."
if [ "$MainVersion" -ge "2302" ]; then
    unzip wsa.zip system.vhdx product.vhdx > /dev/null || abort
else
    unzip wsa.zip system.img product.img > /dev/null || abort
fi
unzip wsa.zip Tools/kernel > /dev/null || abort
mv ./Tools/kernel ./kernel || abort
rm -rf wsa.zip ./Tools || abort
echo "Extract done!"
echo ""

if [ "$MainVersion" -ge "2302" ]; then
    echo "Convert vhdx to img..."
    qemu-img convert -q -f vhdx -O raw system.vhdx system.img || abort
    qemu-img convert -q -f vhdx -O raw product.vhdx product.img || abort
    rm -rf system.vhdx product.vhdx || abort
    echo "Convert done!"
fi
echo ""

mkdir -p ./system || abort
mkdir -p ./product || abort
ImageType=$(blkid -o value -s TYPE system.img) || abort
if [ "$ImageType" == "ext4" ]; then
    echo "Mount ext4 image..."
    fix_ext4_img system.img > /dev/null || abort
    fix_ext4_img product.img > /dev/null || abort
    sudo mount -o loop system.img ./system || abort
    sudo mount -o loop product.img ./product || abort
elif [ "$ImageType" == "erofs" ]; then
    echo "Mount erofs image..."
    sudo chmod 777 ../bin/fuse.erofs || abort
    sudo ../bin/fuse.erofs system.img ./system > /dev/null || abort
    sudo ../bin/fuse.erofs product.img ./product > /dev/null || abort
else
    abort "system image is not supported"
fi
echo "Mount image done!"
echo ""

echo "Check image info:"
echo ""
BuildProp=$(sudo cat ./system/system/build.prop) || abort
AndroidVersion=$(echo "$BuildProp" | sed -n 's/^ro.build.version.release=//p')
API=$(echo "$BuildProp" | sed -n 's/^ro.build.version.sdk=//p')
SeculityPatch=$(echo "$BuildProp" | sed -n 's/^ro.build.version.security_patch=//p')
BuildID=$(echo "$BuildProp" | sed -n 's/^ro.build.id=//p')

KernelInfo=$(file kernel | awk -F ', ' '{print $2}' | sed 's/version //; s/(\(.*\)) //') || abort
KernelMain=$(echo $KernelInfo | cut -d'-' -f1)

WebViewVersion=$(sudo aapt dump badging ./product/app/webview/webview.apk | grep -oP "versionName='\K[^']+") || abort

if [ "$API" == "32" ]; then
    AndroidVersion="12L"
    AndroidInfoURL="https://developer.android.google.cn/about/versions/12/12L"
else
    AndroidInfoURL="https://developer.android.google.cn/about/versions/$AndroidVersion"
fi

SecPatchURL="https://source.android.com/security/bulletin/${SeculityPatch:0:9}1" || abort
SecPatchHead=$(curl -s -L $SecPatchURL | grep -oP '<title>\K[^<]+' | sed 's/&nbsp;//g') || abort
SecPatchDate=$(echo $SecPatchHead | grep -oP '\b[A-Z][a-z]+ \d{4}\b') || abort

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
echo ""

echo "Unmount image..."
sudo umount ./system || abort
sudo umount ./product || abort
echo "Unmount done!"
echo ""

echo "Clean up..."
rm -rf ./system ./product system.img product.img kernel || abort
echo "Clean up done!"