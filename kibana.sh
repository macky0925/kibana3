#!/bin/bash
curl -L http://toolbelt.treasuredata.com/sh/install-redhat.sh|sh

chkconfig td-agent on
service td-agent start

yum install gcc libcurl-devel -y

/usr/lib64/fluent/ruby/bin/fluent-gem install fluent-plugin-elasticsearch

yum install java-1.7.0-openjdk -y

cat << EOF > /etc/yum.repos.d/elasticsearch.repo
[elasticsearch-1.0]
name=Elasticsearch repository for 1.0.x packages
baseurl=http://packages.elasticsearch.org/elasticsearch/1.0/centos
gpgcheck=1
gpgkey=http://packages.elasticsearch.org/GPG-KEY-elasticsearch
enabled=1

EOF

yum install elasticsearch -y

service elasticsearch start
chkconfig elasticsearch on

yum install git -y
cd /var/www/html
git clone https://github.com/elasticsearch/kibana.git kibana
cd kibana
git checkout -b 3.1.2 refs/tags/v3.1.2


chgrp -R td-agent /var/log/httpd/
chmod 770 /var/log/httpd/

cp /etc/td-agent/td-agent.conf /etc/td-agent/td-agent.conf.org

cat << EOF > /etc/td-agent/td-agent.conf
<source>
  type tail
  format apache2
  path /var/log/httpd/access_log
  tag apache.access
  pos_file /var/log/td-agent/apache_access.pos
</source>

<source>
  type tail
  format /^(\[(?<time>[^\]]*)\] \[(?<level>[^\]]+)\] (\[client (?<host>[^\]]*)\] )?(?<message>.*)|(?<message>.*))$/
  path /var/log/httpd/error_log
  tag apache.error
  pos_file /var/log/td-agent/apache_error.pos
</source>

<match apache.access>
  index_name apache_access
  type_name apache_access
  type elasticsearch
  include_tag_key true
  tag_key @log_name
  host localhost
  port 9200
  logstash_format true
  logstash_prefix apache_access
  flush_interval 3s
</match>

<match apache.error>
  type_name apache_error
  type elasticsearch
  include_tag_key true
  tag_key @log_name
  host localhost
  port 9200
  logstash_format true
  logstash_prefix apache_error
  flush_interval 3s
</match>
EOF

curl -XPUT localhost:9200/_template/apache_access -d '
{
   "template" : "apache_access-*",
   "mappings" : {
       "apache_access": {
           "properties": {
                "path" : {"type" : "string", "index": "not_analyzed"},
                "agent" : {"type" : "string", "index": "not_analyzed"}
           }
       }
   }
}'

service td-agent restart

