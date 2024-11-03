#!/system/bin/sh

if [ "$USER" != "root" -a "$(whoami 2>/dev/null)" != "root" ]; then
  echo "autopif2: need root permissions"; exit 1;
fi;
case "$HOME" in
  *termux*) echo "autopif2: need su root environment"; exit 1;;
esac;

case "$1" in
  -h|--help|help) echo "sh autopif2.sh [-a]"; exit 0;;
  -a|--advanced|advanced) ARGS="-a"; shift;;
esac;

echo "Pixel Beta pif.json generator script \
  \n  by osm0sis @ xda-developers & Memory2314";

case "$0" in
  *.sh) DIR="$0";;
  *) DIR="$(lsof -p $$ 2>/dev/null | grep -o '/.*autopif2.sh$')";;
esac;
DIR=$(dirname "$(readlink -f "$DIR")");

item() { echo "\n- $@"; }
die() { echo "\nError: $@, install busybox!"; exit 1; }

find_busybox() {
  [ -n "$BUSYBOX" ] && return 0;
  local path;
  for path in /data/adb/modules/busybox-ndk/system/*/busybox /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox; do
    if [ -f "$path" ]; then
      BUSYBOX="$path";
      return 0;
    fi;
  done;
  return 1;
}

if ! which wget >/dev/null || grep -q "wget-curl" $(which wget); then
  if ! find_busybox; then
    die "wget not found";
  elif $BUSYBOX ping -c1 -s2 android.com 2>&1 | grep -q "bad address"; then
    die "wget broken";
  else
    wget() { $BUSYBOX wget "$@"; }
  fi;
fi;

if date -D '%s' -d "$(date '+%s')" 2>&1 | grep -qE "bad date|invalid option"; then
  if ! find_busybox; then
    die "date broken";
  else
    date() { $BUSYBOX date "$@"; }
  fi;
fi;

if ! echo "A\nB" | grep -m1 -A1 "A" | grep -q "B"; then
  if ! find_busybox; then
    die "grep broken";
  else
    grep() { $BUSYBOX grep "$@"; }
  fi;
fi;

if [ "$DIR" = /data/adb/modules/build_var_spoof ]; then
  DIR=$DIR/autopif2;
  mkdir -p $DIR;
fi;
cd "$DIR";

item "Crawling Android Developers for latest Pixel Beta ...";
wget -q -O PIXEL_VERSIONS_HTML --no-check-certificate https://developer.android.com/about/versions 2>&1 || exit 1;
wget -q -O PIXEL_LATEST_HTML --no-check-certificate $(grep -m1 'developer.android.com/about/versions/' PIXEL_VERSIONS_HTML | cut -d\" -f2) 2>&1 || exit 1;
wget -q -O PIXEL_OTA_HTML --no-check-certificate https://developer.android.com$(grep -om1 'href=".*download-ota"' PIXEL_LATEST_HTML | cut -d\" -f2) 2>&1 || exit 1;
grep -m1 -o 'data-category.*Beta' PIXEL_OTA_HTML | cut -d\" -f2;

BETA_REL_DATE="$(date -D '%B %e, %Y' -d "$(grep -m1 -A1 'Release date' PIXEL_OTA_HTML | tail -n1 | sed 's;.*<td>\(.*\)</td>.*;\1;')" '+%Y-%m-%d')";
BETA_EXP_DATE="$(date -D '%s' -d "$(($(date -D '%Y-%m-%d' -d "$BETA_REL_DATE" '+%s') + 60 * 60 * 24 * 7 * 6))" '+%Y-%m-%d')";
echo "Beta Released: $BETA_REL_DATE \
  \nEstimated Expiry: $BETA_EXP_DATE";

MODEL_LIST="$(grep -A1 'tr id=' PIXEL_OTA_HTML | grep 'td' | sed 's;.*<td>\(.*\)</td>;\1;')";
PRODUCT_LIST="$(grep -o 'ota/.*_beta' PIXEL_OTA_HTML | cut -d\/ -f2)";
OTA_LIST="$(grep 'ota/.*_beta' PIXEL_OTA_HTML | cut -d\" -f2)";

case "$1" in
  -m)
    DEVICE="$(getprop ro.product.device)";
    case "$PRODUCT_LIST" in
      *${DEVICE}_beta*)
        MODEL="$(getprop ro.product.model)";
        PRODUCT="${DEVICE}_beta";
        OTA="$(echo "$OTA_LIST" | grep "$PRODUCT")";
      ;;
    esac;
  ;;
esac;
item "Selecting Pixel Beta device ...";
if [ -z "$PRODUCT" ]; then
  set_random_beta() {
    local list_count="$(echo "$MODEL_LIST" | wc -l)";
    local list_rand="$((RANDOM % $list_count + 1))";
    local IFS=$'\n';
    set -- $MODEL_LIST;
    MODEL="$(eval echo \${$list_rand})";
    set -- $PRODUCT_LIST;
    PRODUCT="$(eval echo \${$list_rand})";
    set -- $OTA_LIST;
    OTA="$(eval echo \${$list_rand})";
    DEVICE="$(echo "$PRODUCT" | sed 's/_beta//')";
  }
  set_random_beta;
fi;
echo "$MODEL ($PRODUCT)";

(ulimit -f 2; wget -q -O PIXEL_ZIP_METADATA --no-check-certificate $OTA) 2>/dev/null;
FINGERPRINT="$(grep -am1 'post-build=' PIXEL_ZIP_METADATA | cut -d= -f2)";
SECURITY_PATCH="$(grep -am1 'security-patch-level=' PIXEL_ZIP_METADATA | cut -d= -f2)";
if [ -z "$FINGERPRINT" -o -z "$SECURITY_PATCH" ]; then
  echo "\nError: Failed to extract information from metadata!";
  exit 1;
fi;

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

item "Dumping values to minimal build_var_spoof ...";
cat <<EOF | tee /data/adb/build_var_spoof/spoof_build_vars;
MANUFACTURER=$BRAND
BRAND=$BRAND
DEVICE=$DEVICE
PRODUCT=$PRODUCT
MODEL=$MODEL
FINGERPRINT=$FINGERPRINT
RELEASE=$RELEASE
ID=$ID
INCREMENTAL=$INCREMENTAL
TYPE=$TYPE
TAGS=$TAGS
SECURITY_PATCH=$SECURITY_PATCH
EOF

item "Killing any running GMS DroidGuard process ...";
killall -v com.google.android.gms.unstable || true;