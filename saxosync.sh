#!/bin/bash

LOCALPATH=$1
REMOTEPATH=$2
SITEURL=$3

if [ -z $LOCALPATH ] || [ -z $REMOTEPATH ] || [ -z $SITEURL ]; then
    echo "Usage: saxosync <Local path> <Remote path> <Base Site url>"
    echo "Example: saxosync /static/web/static/content/sites/NJ/asburypark/app/ /376025/web/static/content/NJ/asburypark/app/ http://content-static.app.com/"
    echo "Note: Local path and base site url must end in '/'"
    exit 1
fi

REMOTEUSER=$4
REMOTEHOST=$5

DELETEDFILES=()
MODIFIEDFILES=()

echo "Running sync.."
echo "Local path: $LOCALPATH"
echo "Remote path: $REMOTEPATH"

rm rsynclog.txt
rm purgeoutput.txt


source /var/lib/google-cloud-sdk/path.bash.inc
export PATH="/var/lib/google-cloud-sdk/bin:$PATH"
export CLOUDSDK_PYTHON="python2.7"
gsutil -m rsync -drC $LOCALPATH gs://content-static-site-com$REMOTEPATH 2>&1 |tee rsynclog.txt

if [ -s rsynclog.txt ]; then
    echo "Log exists, continuing."
else
    echo "No log file. Either no changes exist or there was an error, check job output."
    exit 1
fi

DELETEDFILES=($(grep "Removing" rsynclog.txt | sed 's#Removing gs://content-static-site-com/376025/web/static/content/[A-Za-z-]*/[A-Za-z-]*/[A-Za-z-]*/##g'))
MODIFIEDFILES=($(grep "Copying" rsynclog.txt|sed 's#Copying file:///static/web/static/content/sites/[A-Za-z-]*/[A-Za-z-]*/[A-Za-z-]*/\(.*\) .*#\1#'))


if [ ${#DELETEDFILES[@]} -eq 0 ] && [ ${#MODIFIEDFILES[@]} -eq 0 ]; then
    echo "No files to purge, exiting"
    exit 0
fi

echo "I will purge ${#DELETEDFILES[@]} deleted files and ${#MODIFIEDFILES[@]} modified files"

URLLIST=""

for i in ${DELETEDFILES[@]} ${MODIFIEDFILES[@]}; do 
echo $i
    if [ -z $URLLIST ]; then
        URLLIST="$SITEURL$i"
    else
        URLLIST="$URLLIST,\"$SITEURL$i\""
    fi
done

URLLIST="$URLLIST"

echo "Payload being sent to Fastly for cache purging: $URLLIST"

echo curl -X PURGE "$URLLIST" | tee purgeoutput.txt

RESPONSE=$(cat purgeoutput.txt|head -1|awk '{print $2}')

if [ "$RESPONSE" -ne "201" ]; then
    echo "ERROR: Got response $RESPONSE from Fastly, expecting 201."
    exit 1
fi

