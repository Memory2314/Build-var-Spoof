#!/bin/sh
PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:/data/data/com.termux/files/usr/bin:$PATH
MODDIR=/data/adb/modules/build_var_spoof

download() { busybox wget -T 10 --no-check-certificate -qO - "$1" > "$2" || download_fail "$1"; }
if command -v curl > /dev/null 2>&1; then
    download() { curl --connect-timeout 10 -s "$1" > "$2" || download_fail "$1"; }
fi

download_fail() {
	echo "[!] download failed!"
	echo "[x] bailing out!"
	exit 1
}

set_random_beta() {
    if [ "$(echo "$MODEL_LIST" | wc -l)" -ne "$(echo "$PRODUCT_LIST" | wc -l)" ]; then
            echo "Error: MODEL_LIST and PRODUCT_LIST have different lengths."
            exit 1
    fi
    count=$(echo "$MODEL_LIST" | wc -l)
    rand_index=$(( $$ % count ))
    MODEL=$(echo "$MODEL_LIST" | sed -n "$((rand_index + 1))p")
    PRODUCT=$(echo "$PRODUCT_LIST" | sed -n "$((rand_index + 1))p")
    OTA=$(echo "$OTA_LIST" | sed -n "$((rand_index + 1))p")
    DEVICE=$(echo "$PRODUCT" | sed 's/_beta//')
}

sleep_pause() {
    # APatch and KernelSU needs this
    # but not KSU_NEXT, MMRL
    if [ -z "$MMRL" ] && [ -z "$KSU_NEXT" ] && { [ "$KSU" = "true" ] || [ "$APATCH" = "true" ]; }; then
        sleep 5
    fi
}

TEMPDIR="$MODDIR/temp"
rm -rf "$TEMPDIR"
mkdir -p "$TEMPDIR"
cd "$TEMPDIR"

# Get latest Pixel Beta information
echo "- Get latest Pixel Beta information"
download https://developer.android.com/about/versions PIXEL_VERSIONS_HTML
BETA_URL=$(grep -o 'https://developer.android.com/about/versions/.*[0-9]"' PIXEL_VERSIONS_HTML | sort -ru | cut -d\" -f1 | head -n1)
download "$BETA_URL" PIXEL_LATEST_HTML

# Handle Developer Preview vs Beta
echo "- Handle Developer Preview vs Beta"
if grep -qE 'Developer Preview|tooltip>.*preview program' PIXEL_LATEST_HTML && [ "$FORCE_PREVIEW" = 0 ]; then
	# Use the second latest version for beta
	echo "- Use the second latest version for beta"
	BETA_URL=$(grep -o 'https://developer.android.com/about/versions/.*[0-9]"' PIXEL_VERSIONS_HTML | sort -ru | cut -d\" -f1 | head -n2 | tail -n1)
	download "$BETA_URL" PIXEL_BETA_HTML
else
	mv -f PIXEL_LATEST_HTML PIXEL_BETA_HTML
fi

# Get OTA information
echo "- Get OTA information"
OTA_URL="https://developer.android.com$(grep -o 'href=".*download-ota.*"' PIXEL_BETA_HTML | cut -d\" -f2 | head -n1)"
download "$OTA_URL" PIXEL_OTA_HTML

# Extract device information
MODEL_LIST="$(grep -A1 'tr id=' PIXEL_OTA_HTML | grep 'td' | sed 's;.*<td>\(.*\)</td>;\1;')"
PRODUCT_LIST="$(grep -o 'tr id="[^"]*"' PIXEL_OTA_HTML | awk -F\" '{print $2 "_beta"}')"
OTA_LIST="$(grep 'ota/.*_beta' PIXEL_OTA_HTML | cut -d\" -f2)"

# Select and configure device
echo "- Selecting Pixel Beta device ..."
[ -z "$PRODUCT" ] && set_random_beta
echo "$MODEL ($PRODUCT)"

# Get device fingerprint and security patch from OTA metadata
(ulimit -f 2; download "$(echo "$OTA_LIST" | grep "$PRODUCT")" PIXEL_ZIP_METADATA) >/dev/null 2>&1
FINGERPRINT="$(strings PIXEL_ZIP_METADATA | grep -am1 'post-build=' | cut -d= -f2)"
SECURITY_PATCH="$(strings PIXEL_ZIP_METADATA | grep -am1 'security-patch-level=' | cut -d= -f2)"

# Validate required field to prevent empty spoof_build_vars
if [ -z "$FINGERPRINT" ] || [ -z "$SECURITY_PATCH" ]; then
	# link to download pixel rom metadata that skipped connection check due to ulimit
	download_fail "https://dl.google.com"
fi

# Preserve previous setting
spoofConfig="spoofVendingSdk"
for config in $spoofConfig; do
	if grep -q "\"$config\": true" "$MODDIR/spoof_build_vars"; then
		eval "$config=true"
	else
		eval "$config=false"
	fi
done

echo "- Dumping values to spoof_build_vars ..."
if [ -n "$FINGERPRINT" ]; then
    BRAND=$(echo $FINGERPRINT | cut -d'/' -f1)
    PRODUCT=$(echo $FINGERPRINT | cut -d'/' -f2)
    DEVICE=$(echo $FINGERPRINT | cut -d'/' -f3 | cut -d':' -f1)
    RELEASE=$(echo $FINGERPRINT | cut -d':' -f2 | cut -d'/' -f1)
    ID=$(echo $FINGERPRINT | cut -d'/' -f4)
    INCREMENTAL=$(echo $FINGERPRINT | cut -d'/' -f5 | cut -d':' -f1)
    TYPE=$(echo $FINGERPRINT | cut -d':' -f3 | cut -d'/' -f1)
    TAGS=$(echo $FINGERPRINT | cut -d':' -f3 | cut -d'/' -f2)
fi
cat <<EOF | tee spoof_build_vars
MANUFACTURER=Google
MODEL=$MODEL
FINGERPRINT=$FINGERPRINT
BRAND=$BRAND
PRODUCT=$PRODUCT
DEVICE=$DEVICE
RELEASE=$RELEASE
ID=$ID
INCREMENTAL=$INCREMENTAL
TYPE=$TYPE
TAGS=$TAGS
SECURITY_PATCH=$SECURITY_PATCH
EOF

cat "$TEMPDIR/spoof_build_vars" > /data/adb/build_var_spoof/spoof_build_vars
echo "- new spoof_build_vars saved to data/adb/build_var_spoof/spoof_build_vars"

echo "- Cleaning up ..."
rm -rf "$TEMPDIR"

for i in $(busybox pidof com.google.android.gms.unstable); do
	echo "- Killing pid $i"
	kill -9 "$i"
done

echo "- Done!"
sleep_pause