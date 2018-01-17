#!/bin/bash
#
# This script takes a path to a file and uploads it to Amazon
# Glacier. It does this in several steps:
#
#    1. Split the file up into 1MiB chunks.
#    2. Initiate a multipart upload.
#    3. Upload each part individually.
#    4. Calculate the file's tree hash and finish the upload.
#
#
# Author: Damien Radtke <damienradtke at gmail dot com>
# Extended by Dimitrios Bantanis-Kapirnas (https://jbkhellas.com)
# License: WTFPL

# Set this to the name of the Glacier vault to upload to.

VAULT_NAME="NAME_OF_VAULT"

# 512MB per chunk; you can set it to 1MB, 2MB, 4MB, 8MB ... 512MB
CHUNK_SIZE=536870912

# 8MB
#CHUNK_SIZE=8388608


TIMESTAMP=$(date +"%F")
BACKUP_DIR="/path/to/folder/with/files/*"
IDFILE="${TIMESTAMP}-archive-ids.json"
mkdir tempchunkfolder
cd tempchunkfolder

for f in $BACKUP_DIR
do
base=$(basename "$f");
ARCHIVE=$f
ARCHIVE_SIZE=`cat "${ARCHIVE}" | wc --bytes`

echo "Initiating multipart upload... ${base}"

# Split the archive into chunks.
split --bytes=${CHUNK_SIZE} "${ARCHIVE}" chunk
NUM_CHUNKS=`ls chunk* | wc -l`

# Initiate upload.
UPLOAD_ID=$(/usr/local/bin/aws glacier initiate-multipart-upload \
    --account-id=- \
    --vault-name="${VAULT_NAME}" \
    --archive-description="${TIMESTAMP}/$f" \
    --part-size=${CHUNK_SIZE} \
    --query=uploadId | sed 's/"//g')

# Abort the upload if forced to exit.
function abort_upload {
    echo "Aborting upload."
    /usr/local/bin/aws glacier abort-multipart-upload \
        --account-id=- \
        --vault-name="${VAULT_NAME}" \
        --upload-id="${UPLOAD_ID}"
}
trap abort_upload SIGINT SIGTERM

RETVAL=$?
if [[ ${RETVAL} -ne 0 ]]; then
    echo "initiate-multipart-upload failed with status code: ${RETVAL}"
    exit 1
fi
echo "Upload ID: ${UPLOAD_ID}"



# Loop through the chunks.
INDEX=0
for CHUNK in chunk*; do
    # Calculate the byte range for this chunk.
    START=$((INDEX*CHUNK_SIZE))
    END=$((((INDEX+1)*CHUNK_SIZE)-1))
    END=$((END>(ARCHIVE_SIZE-1)?ARCHIVE_SIZE-1:END))
    # Increment the index.
    INDEX=$((INDEX+1))

    while true; do
        echo "Uploading chunk ${INDEX} / ${NUM_CHUNKS}..."
        /usr/local/bin/aws glacier upload-multipart-part \
            --account-id=- \
            --vault-name="${VAULT_NAME}" \
            --upload-id="${UPLOAD_ID}" \
            --body="${CHUNK}" \
            --range="bytes ${START}-${END}/*" \
            >/dev/null
        RETVAL=$?
        if [[ ${RETVAL} -eq 0 ]]; then
            # Upload succeeded, on to the next one.
            break
        elif [[ ${RETVAL} -eq 130 ]]; then
            # Received a SIGINT.
            exit 1
        elif [[ ${RETVAL} -eq 255 ]]; then
            # Most likely a timeout, just let it try again.
            echo "Chunk ${INDEX} ran into an error, retrying..."
            sleep 1
        else
            echo "upload-multipart-part failed with status code: ${RETVAL}"
            echo "Aborting upload."
            /usr/local/bin/aws glacier abort-multipart-upload \
                --account-id=- \
                --vault-name="${VAULT_NAME}" \
                --upload-id="${UPLOAD_ID}"
            exit 1
        fi
    done
	
   
done

for CHUNK in chunk*; do
rm ${CHUNK}
done
# Calculate tree hash.
# ("And now for the tricky bit.")
echo "Calculating tree hash..."
echo "Finalizing..."
checksum=`java -classpath /var/BKP/DO_NOT_DELETE/glacier TreeHashExample ${ARCHIVE} | cut -d ' ' -f 5`
echo "$checksum"
 echo "# $ARCHIVE" >> $IDFILE
/usr/local/bin/aws glacier complete-multipart-upload \
    --account-id=- \
    --vault-name="${VAULT_NAME}" \
    --upload-id="${UPLOAD_ID}" \
    --checksum="${checksum}" \
    --archive-size=${ARCHIVE_SIZE} >> $IDFILE
RETVAL=$?
if [[ ${RETVAL} -ne 0 ]]; then
    echo "complete-multipart-upload failed with status code: ${RETVAL}"
    echo "Aborting upload ${UPLOAD_ID}"
    /usr/local/bin/aws glacier abort-multipart-upload \
        --account-id=- \
        --vault-name="${VAULT_NAME}" \
        --upload-id="${UPLOAD_ID}"
    exit 1
fi

echo "Done."
done
exit 0