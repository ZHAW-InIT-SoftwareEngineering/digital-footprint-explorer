#!/bin/sh

if [ -z "${UPLOAD_SECRET:-}" ]; then
    echo "Error: environment variable UPLOAD_SECRET is not set." >&2
    exit 1
fi

# Show the status code and headers
curl -i -X POST https://greensoftware.ch/dfe/upload.php -H "X-API-Key: $UPLOAD_SECRET" -F "file=@./test_files/test.zip"

# Check that the server rejects a file that isn't a ZIP (should return 415)
curl -i -X POST https://greensoftware.ch/dfe/upload.php -H "X-API-Key: $UPLOAD_SECRET" -F "file=@./test_files/text.txt"

# Check that a missing or wrong API key is rejected (should return 401)
curl -i -X POST https://greensoftware.ch/dfe/upload.php -F "file=@./test_files/test.zip"