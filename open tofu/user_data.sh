#!/bin/bash
exec > /var/log/user-data.log 2>&1
echo "userdata-start"
set -eux

apt update
apt install -y python3-pip python3.12-venv git

cd /home/ubuntu

git clone ${git_repo} projet
cd projet/webservice

python3 -m venv venv
source venv/bin/activate

cat > .env <<EOF
BUCKET=${bucket}
DYNAMO_TABLE=${dynamo_table}
EOF

export BUCKET="${bucket}"
export DYNAMO_TABLE="${dynamo_table}"

pip install --upgrade pip
pip install -r requirements.txt

nohup venv/bin/python app.py > app.log 2>&1 &

sleep 5
curl -I http://localhost:8080/docs || true

echo "userdata-end"