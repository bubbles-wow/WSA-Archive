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

cd ./download || abort
if [ "$(find . -name "*.Msixbundle" | wc -l)" == "0" ]; then
    abort "No package found!"
fi
while [ -n "$(find . -name "*.Msixbundle" | head -n 1)" ]; do
    FileName=$(find . -name "*.Msixbundle" | head -n 1 | xargs -I {} basename {}) || abort
    PackageVersion=$(unzip -l "$FileName" | grep "WsaPackage_\([0-9]\+\.\)\{3\}[0-9]\+_x64_Release-Nightly.msix" | cut -d'_' -f2) || abort
    if [ -z "$PackageVersion" ]; then
        echo "Bad package! Remove this..."
        echo ""
        rm -rf "$FileName" || abort
        continue
    fi
    mv "$FileName" wsa.zip || abort
    echo "Found package: $FileName"
    echo ""
    
    echo "Extract package..."
    unzip wsa.zip "WsaPackage_${PackageVersion}_x64_Release-Nightly.msix" > /dev/null || abort
    rm -rf wsa.zip || abort
    mv "WsaPackage_${PackageVersion}_x64_Release-Nightly.msix" wsa.zip || abort
    echo "Extract done!"
    echo ""
    
    echo "Extract image and kernel..."
    # shellcheck disable=SC2071
    if [ "$PackageVersion" \> "2302" ]; then
        unzip wsa.zip system.vhdx product.vhdx > /dev/null || abort
    else
        unzip wsa.zip system.img product.img >/dev/null || abort
    fi
    unzip wsa.zip Tools/kernel > /dev/null || abort
    mv ./Tools/kernel ./kernel || abort
    rm -rf wsa.zip ./Tools || abort
    echo "Extract done!"
    echo ""
    
    # shellcheck disable=SC2071
    if [ "$PackageVersion" \> "2302" ]; then
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
    AndroidInfoURL="https://developer.android.google.cn/about/versions/$AndroidVersion"
    if [ "$API" == "32" ]; then
        AndroidVersion="12L"
        AndroidInfoURL="https://developer.android.google.cn/about/versions/12/12L"
    fi
    
    KernelInfo=$(file kernel | awk -F ', ' '{print $2}' | sed 's/version //; s/(\(.*\)) //') || abort
    KernelMain=$(echo "$KernelInfo" | cut -d'-' -f1)
    KernelHead="latte"
    # shellcheck disable=SC2072
    if [ "$KernelMain" \> "5.15" ]; then
        KernelHead="latte-2"
    fi
    
    WebViewVersion=$(sudo aapt dump badging ./product/app/webview/webview.apk | grep -oP "versionName='\K[^']+") || abort
    
    SecPatchURL="https://source.android.com/docs/security/bulletin/${SeculityPatch:0:9}1" || abort
    SecPatchHead=$(curl -s -L "$SecPatchURL" | grep -oP '<title>\K[^<]+' | sed 's/&nbsp;//g') || abort
    SecPatchDate=$(echo "$SecPatchHead" | grep -oP '\b[A-Z][a-z]+ \d{4}\b') || abort
    
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
- Seculity Patch
  \`\`\`
  $SeculityPatch
  \`\`\`
Note: [Android Security Bulletin—**$SecPatchDate** | Android Open Source Project]($SecPatchURL)
- Kernel Version
  \`\`\`
  $KernelInfo
  \`\`\`
Source: [$KernelHead/**$KernelMain**](https://github.com/microsoft/WSA-Linux-Kernel/)
- Build ID
  \`\`\`
  $BuildID
  \`\`\`
- Chromium WebView Version
  \`\`\`
  $WebViewVersion
  \`\`\`"
    
    touch "$PackageVersion.md" || abort
    sudo echo "$Description" | sudo tee "$PackageVersion.md" > /dev/null || abort
    echo ""
    
    echo "Unmount image..."
    sudo umount ./system || abort
    sudo umount ./product || abort
    echo "Unmount done!"
    echo ""
    
    echo "Clean up..."
    rm -rf ./system ./product system.img product.img kernel || abort
    echo "Clean up done!"
    echo ""
done
echo "All done!"
