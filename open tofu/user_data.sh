#!/bin/bash
echo "userdata-start"
set -e

apt update
apt install -y python3-pip python3.12-venv git

git clone ${git_repo} projet
cd projet/webservice

python3 -m venv venv
source venv/bin/activate

rm -f .env

cat > .env <<EOF
BUCKET=${bucket}
DYNAMO_TABLE=${dynamo_table}
EOF

export BUCKET="${bucket}"
export DYNAMO_TABLE="${dynamo_table}"

pip install -r requirements.txt

nohup venv/bin/python app.py > app.log 2>&1 &
echo "userdata-end"