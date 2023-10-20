#!/bin/bash

abort() {
    [ "$1" ] && echo -e "ERROR: $1"
    echo "Build: an error has occurred, exit"
    exit 1
}

vhdx_to_raw_img() {
    qemu-img convert -q -f vhdx -O raw "$1" "$2" || return 1
    rm -f "$1" || return 1
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

check_image_type() {
    local type
    type=$(blkid -o value -s TYPE "$1")
    echo "$type"
}

cd ./download
file_name=$(ls *.Msixbundle)
version=$(echo $file_name | cut -d'_' -f2)
mv $file_name wsa.zip || abort
unzip wsa.zip "WsaPackage_${version}_x64_Release-Nightly.msix" || abort
rm -rf wsa.zip || abort
mv "WsaPackage_${version}_x64_Release-Nightly.msix" wsa.zip || abort
if [ "$version" \< "2302" ]; then
    unzip wsa.zip system.img product.img || abort
else
    unzip wsa.zip system.vhdx product.vhdx || abort
    vhdx_to_raw_img system.vhdx system.img || abort
    vhdx_to_raw_img product.vhdx product.img || abort
fi
unzip wsa.zip Tools/kernel || abort
mv ./Tools/kernel ./kernel || abort
rm -rf wsa.zip ./Tools || abort
image_type=$(check_image_type system.img) || abort
if [ "$image_type" == "ext4" ]; then
    ro_ext4_img_to_rw system.img || abort
    ro_ext4_img_to_rw product.img || abort
else
    abort "system image is not supported"
fi
mkdir -p ./system || abort
mkdir -p ./product || abort
resize_img system.img || abort
resize_img product.img || abort
sudo mount -o loop system.img ./system || abort
sudo mount -o loop product.img ./product || abort

AndroidVersion=$(sed -n 's/^ro.build.version.release=//p' ./system/system/build.prop)
API=$(sed -n 's/^ro.build.version.sdk=//p' ./system/system/build.prop)
SeculityPatch=$(sed -n 's/^ro.build.version.security_patch=//p' ./system/system/build.prop)
BuildID=$(sed -n 's/^ro.build.id=//p' ./system/system/build.prop)
Kernel=$(file kernel | awk -F ': ' '{print $2}' | awk -F ' ' '{print $8, $10, $11, $12, $13, $14, $15, $16, $17, $18}' | cut -d',' -f1)
WebViewVersion=$(aapt dump badging ./product/app/webview/webview.apk | grep -oP "versionName='\K[^']+")

echo "AndroidVersion: $AndroidVersion"
echo "WebViewVersion: $WebViewVersion"
echo "API: $API"
echo "SeculityPatch: $SeculityPatch"
echo "BuildID: $BuildID"
echo "Kernel: $Kernel"

AndroidInfoURL="https://developer.android.google.cn/about/versions/$AndroidVersion"
SecPatchURL="https://source.android.com/security/bulletin/$SeculityPatch"
SecPatchHead=$(curl -s -L $SecPatchURL | grep -oP '<title>\K[^<]+' | sed 's/&nbsp;//g')

Description="
## Details
  - [Android $AndroidVersion]($AndroidInfoURL) | API $API
  - Seculity patch
    \`\`\`
    $SeculityPatch
    \`\`\`
    Note: [$SecPatchHead]($SecPatchURL)
  - Kernel Version
    \`\`\`
    $Kernel
    \`\`\`
  - Build ID: 
    \`\`\`
    $BuildID
    \`\`\`"
  - Chromium WebView $WebViewVersion

echo "$Description" > ./INFO.md || abort

sudo umount ./system || abort
sudo umount ./product || abort
rm -rf ./system ./product system.img product.img kernel || abort