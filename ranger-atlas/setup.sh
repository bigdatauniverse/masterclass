#!/usr/bin/env bash
set -o xtrace

########################################################################
########################################################################
## variables

export HOME=${HOME:-/root}
export TERM=xterm
: ${ambari_pass:="BadPass#1"}
ambari_password="${ambari_pass}"
: ${stack:="mycluster"}
: ${cluster_name:=${stack}}
: ${ambari_services:="HDFS MAPREDUCE2 PIG YARN HIVE ZOOKEEPER AMBARI_METRICS SLIDER AMBARI_INFRA TEZ RANGER ATLAS KAFKA SPARK ZEPPELIN"}
: ${install_ambari_server:=true}
: ${ambari_stack_version:=2.6}
: ${deploy:=true}
: ${host_count:=skip}
: ${recommendation_strategy:="ALWAYS_APPLY_DONT_OVERRIDE_CUSTOM_VALUES"}

## overrides
#export ambari_stack_version=2.6
#export ambari_repo=https://public-repo-1.hortonworks.com/ambari/centos7/2.x/updates/2.5.0.3/ambari.repo

export ambari_pass ambari_password stack cluster_name ambari_services install_ambari_server
export ambari_stack_version deploy host_count recommendation_strategy

########################################################################
########################################################################
## 
cd

yum makecache
yum -y -q install git epel-release ntpd screen mysql-connector-java jq python-argparse python-configobj ack
curl -sSL https://raw.githubusercontent.com/seanorama/ambari-bootstrap/master/extras/deploy/install-ambari-bootstrap.sh | bash


########################################################################
########################################################################
## tutorial users
users="kate-hr ivana-eu-hr joe-analyst hadoop-admin compliance-admin hadoopadmin"
for user in ${users}; do
    sudo useradd ${user}
    printf "${ambari_pass}\n${ambari_pass}" | sudo passwd --stdin ${user}
    echo "${user} ALL=(ALL) NOPASSWD:ALL" | sudo tee -a /etc/sudoers.d/99-masterclass
done
groups="hr analyst compliance us_employees eu_employees hadoop-users hadoop-admins"
for group in ${groups}; do
  groupadd ${group}
done
usermod -a -G hr kate-hr
usermod -a -G hr ivana-eu-hr
usermod -a -G analyst joe-analyst
usermod -a -G compliance compliance-admin
usermod -a -G us_employees kate-hr
usermod -a -G us_employees joe-analyst
usermod -a -G us_employees compliance-admin
usermod -a -G eu_employees ivana-eu-hr
usermod -a -G hadoop-admins hadoopadmin
usermod -a -G hadoop-admins hadoop-admin

########################################################################
########################################################################
## 
~/ambari-bootstrap/extras/deploy/prep-hosts.sh
~/ambari-bootstrap/ambari-bootstrap.sh

## Ambari Server specific tasks
if [ "${install_ambari_server}" = "true" ]; then

    ## add admin user to postgres for other services, such as Ranger
    cd /tmp
    sudo -u postgres createuser -U postgres -d -e -E -l -r -s admin
    sudo -u postgres psql -c "ALTER USER admin PASSWORD 'BadPass#1'";
    printf "\nhost\tall\tall\t0.0.0.0/0\tmd5\n" >> /var/lib/pgsql/data/pg_hba.conf
    systemctl restart postgresql

    ## bug workaround:
    sed -i "s/\(^    total_sinks_count = \)0$/\11/" /var/lib/ambari-server/resources/stacks/HDP/2.0.6/services/stack_advisor.py
    bash -c "nohup ambari-server restart" || true
    
    ambari_pass=admin source ~/ambari-bootstrap/extras/ambari_functions.sh
    until [ $(ambari_pass=BadPass#1 ${ambari_curl}/hosts -o /dev/null -w "%{http_code}") -eq "200" ]; do
        sleep 1
    done
    ambari_change_pass admin admin ${ambari_pass}

    yum -y install postgresql-jdbc
    ambari-server setup --jdbc-db=postgres --jdbc-driver=/usr/share/java/postgresql-jdbc.jar
    ambari-server setup --jdbc-db=mysql --jdbc-driver=/usr/share/java/mysql-connector-java.jar

    cd ~/ambari-bootstrap/deploy

        ## various configuration changes for demo environments, and fixes to defaults
cat << EOF > configuration-custom.json
{
  "configurations" : {
    "core-site": {
        "hadoop.proxyuser.root.users" : "admin",
        "fs.trash.interval": "4320"
    },
    "hdfs-site": {
      "dfs.namenode.safemode.threshold-pct": "0.99"
    },
    "hive-site": {
        "hive.server2.enable.doAs" : "true",
        "hive.server2.transport.mode": "http",
        "hive.exec.compress.output": "true",
        "hive.merge.mapfiles": "true",
        "hive.server2.tez.initialize.default.sessions": "true",
        "hive.exec.post.hooks" : "org.apache.hadoop.hive.ql.hooks.ATSHook,org.apache.atlas.hive.hook.HiveHook",
        "hive.server2.tez.initialize.default.sessions": "true"
    },
    "mapred-site": {
        "mapreduce.job.reduce.slowstart.completedmaps": "0.7",
        "mapreduce.map.output.compress": "true",
        "mapreduce.output.fileoutputformat.compress": "true"
    },
    "yarn-site": {
        "yarn.acl.enable" : "true"
    },
    "ams-site": {
      "timeline.metrics.cache.size": "100"
    },
    "admin-properties": {
        "policymgr_external_url": "http://localhost:6080",
        "db_root_user": "admin",
        "db_root_password": "BadPass#1",
        "DB_FLAVOR": "POSTGRES",
        "db_user": "rangeradmin",
        "db_password": "BadPass#1",
        "db_name": "ranger",
        "db_host": "localhost"
    },
    "ranger-env": {
        "ranger_admin_username": "admin",
        "ranger_admin_password": "admin",
          "ranger-knox-plugin-enabled" : "No",
          "ranger-storm-plugin-enabled" : "No",
          "ranger-kafka-plugin-enabled" : "No",
        "ranger-hdfs-plugin-enabled" : "Yes",
        "ranger-hive-plugin-enabled" : "Yes",
        "ranger-hbase-plugin-enabled" : "Yes",
        "ranger-atlas-plugin-enabled" : "Yes",
        "ranger-yarn-plugin-enabled" : "Yes",
        "is_solrCloud_enabled": "true",
        "xasecure.audit.destination.solr" : "true",
        "xasecure.audit.destination.hdfs" : "true",
        "ranger_privelege_user_jdbc_url" : "jdbc:postgresql://localhost:5432/postgres",
        "create_db_dbuser": "true"
    },
    "ranger-admin-site": {
        "ranger.jpa.jdbc.driver": "org.postgresql.Driver",
        "ranger.jpa.jdbc.url": "jdbc:postgresql://localhost:5432/ranger"
    },
    "ranger-hive-audit" : {
        "xasecure.audit.is.enabled" : "true",
        "xasecure.audit.destination.hdfs" : "true",
        "xasecure.audit.destination.solr" : "true",
        "xasecure.audit.destination.solr.zookeepers" : "localhost:2181/infra-solr"
    },
    "application-properties": {
        "atlas.cluster.name.off":"${cluster_name}",
        "atlas.feature.taxonomy.enable":"true",
        "atlas.kafka.bootstrap.servers": "localhost:6667",
        "atlas.kafka.zookeeper.connect": "localhost:2181",
        "atlas.kafka.zookeeper.connection.timeout.ms": "20000",
        "atlas.kafka.zookeeper.session.timeout.ms": "40000",
        "atlas.rest.address": "http://localhost:21000",
        "atlas.graph.storage.backend": "berkeleyje",
        "atlas.graph.storage.hostname": "localhost",
        "atlas.graph.storage.directory": "/tmp/data/berkeley",
        "atlas.EntityAuditRepository.impl": "org.apache.atlas.repository.audit.NoopEntityAuditRepository",
        "atlas.graph.index.search.backend": "elasticsearch",
        "atlas.graph.index.search.directory": "/tmp/data/es",
        "atlas.graph.index.search.elasticsearch.client-only": "false",
        "atlas.graph.index.search.elasticsearch.local-mode": "true",
        "atlas.graph.index.search.elasticsearch.create.sleep": "2000",
        "atlas.notification.embedded": "false",
        "atlas.graph.index.search.solr.zookeeper-url": "localhost:2181/infra-solr",
        "atlas.audit.hbase.zookeeper.quorum": "localhost",
        "atlas.graph.storage.hostname": "localhost",
        "atlas.kafka.data": "/tmp/data/kafka"
    },
    "atlas-env" : {
        "content" : "\n      # The java implementation to use. If JAVA_HOME is not found we expect java and jar to be in path\n      export JAVA_HOME={{java64_home}}\n\n      # any additional java opts you want to set. This will apply to both client and server operations\n      {% if security_enabled %}\n      export ATLAS_OPTS=\"{{metadata_opts}} -Djava.security.auth.login.config={{atlas_jaas_file}}\"\n      {% else %}\n      export ATLAS_OPTS=\"{{metadata_opts}}\"\n      {% endif %}\n\n      # metadata configuration directory\n      export ATLAS_CONF={{conf_dir}}\n\n      # Where log files are stored. Defatult is logs directory under the base install location\n      export ATLAS_LOG_DIR={{log_dir}}\n\n      # additional classpath entries\n      export ATLASCPPATH={{metadata_classpath}}\n\n      # data dir\n      export ATLAS_DATA_DIR={{data_dir}}\n\n      # pid dir\n      export ATLAS_PID_DIR={{pid_dir}}\n\n      # hbase conf dir\n      export MANAGE_LOCAL_HBASE=false\n export MANAGE_LOCAL_SOLR=false\n\n\n      # Where do you want to expand the war file. By Default it is in /server/webapp dir under the base install dir.\n      export ATLAS_EXPANDED_WEBAPP_DIR={{expanded_war_dir}}\n      export ATLAS_SERVER_OPTS=\"-server -XX:SoftRefLRUPolicyMSPerMB=0 -XX:+CMSClassUnloadingEnabled -XX:+UseConcMarkSweepGC -XX:+CMSParallelRemarkEnabled -XX:+PrintTenuringDistribution -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=$ATLAS_LOG_DIR/atlas_server.hprof -Xloggc:$ATLAS_LOG_DIRgc-worker.log -verbose:gc -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=10 -XX:GCLogFileSize=1m -XX:+PrintGCDetails -XX:+PrintHeapAtGC -XX:+PrintGCTimeStamps\"\n      {% if java_version == 8 %}\n      export ATLAS_SERVER_HEAP=\"-Xms{{atlas_server_xmx}}m -Xmx{{atlas_server_xmx}}m -XX:MaxNewSize={{atlas_server_max_new_size}}m -XX:MetaspaceSize=100m -XX:MaxMetaspaceSize=512m\"\n      {% else %}\n      export ATLAS_SERVER_HEAP=\"-Xms{{atlas_server_xmx}}m -Xmx{{atlas_server_xmx}}m -XX:MaxNewSize={{atlas_server_max_new_size}}m -XX:MaxPermSize=512m\"\n      {% endif %}"
    }
  }
}
EOF

    sleep 1
    ./deploy-recommended-cluster.bash

    if [ "${deploy}" = "true" ]; then

        cd ~
        sleep 5
        source ~/ambari-bootstrap/extras/ambari_functions.sh
        ambari_configs
        ambari_wait_request_complete 1
        cd ~
        sleep 10

        usermod -a -G users ${USER}
        usermod -a -G users admin
        echo "${ambari_pass}" | passwd admin --stdin
        sudo sudo -u hdfs bash -c "
            hadoop fs -mkdir /user/admin;
            hadoop fs -chown admin /user/admin;
            hdfs dfsadmin -refreshUserToGroupsMappings"

        UID_MIN=$(awk '$1=="UID_MIN" {print $2}' /etc/login.defs)
        users="$(getent passwd|awk -v UID_MIN="${UID_MIN}" -F: '$3>=UID_MIN{print $1}')"
        for user in ${users}; do sudo usermod -a -G users ${user}; done
        for user in ${users}; do sudo usermod -a -G hadoop-users ${user}; done
        ~/ambari-bootstrap/extras/onboarding.sh

        cd ~/
        git clone https://github.com/seanorama/masterclass
        cd ~/masterclass/ranger-atlas/Scripts/
        ./create-secgovdemo-hortoniabank-userfolders.sh
        yum -y install bzip2
        ./load-secgovdemo-hortoniabank-files.sh

        ## update ranger to support deny policies
        ranger_curl="curl -u admin:admin"
        ranger_url="http://localhost:6080/service"
        ${ranger_curl} ${ranger_url}/public/v2/api/servicedef/name/hive \
          | jq '.options = {"enableDenyAndExceptionsInPolicies":"true"}' \
          | jq '.policyConditions = [
        {
              "itemId": 1,
              "name": "resources-accessed-together",
              "evaluator": "org.apache.ranger.plugin.conditionevaluator.RangerHiveResourcesAccessedTogetherCondition",
              "evaluatorOptions": {},
              "label": "Resources Accessed Together?",
              "description": "Resources Accessed Together?"
        },{
            "itemId": 2,
            "name": "not-accessed-together",
            "evaluator": "org.apache.ranger.plugin.conditionevaluator.RangerHiveResourcesNotAccessedTogetherCondition",
            "evaluatorOptions": {},
            "label": "Resources Not Accessed Together?",
            "description": "Resources Not Accessed Together?"
        }
        ]' > hive.json

        ${ranger_curl} -i \
          -X PUT -H "Accept: application/json" -H "Content-Type: application/json" \
          -d @hive.json ${ranger_url}/public/v2/api/servicedef/name/hive
        sleep 5

        ## import ranger policies
        < ranger-policies.json jq '.policies[].service = "'${cluster_name}'_hive"' > ranger-policies-apply.json
        ${ranger_curl} -X POST \
        -H "Content-Type: multipart/form-data" \
        -H "Content-Type: application/json" \
        -F 'file=@ranger-policies-apply.json' \
                  "${ranger_url}/plugins/policies/importPoliciesFromFile?isOverride=true&serviceType=hive"

        sleep 30
        ./create-secgovdemo-hortoniabank-tables.sh


        #${ranger_curl} -v ${ranger_url}/users/1/passwordchange \
          #-H 'Content-Type: application/json' \
          #-d '{"loginId":"admin","emailAddress":"","oldPassword":"admin","updPassword":"BadPass#1"}'
        #sed -i.backup 's/\(admin=ADMIN::\).*/\19cf30fbdf6297c772d2724f2e81a423c09deb8f70a0ee92a0f6bbd03ad3e151b/' /usr/hdp/current/atlas-server/conf/users-credentials.properties

        #sudo curl -u admin:${ambari_pass} -H 'X-Requested-By: blah' -X POST -d "
#{
   #\"RequestInfo\":{
      #\"command\":\"RESTART\",
      #\"context\":\"Restart Atlas\",
      #\"operation_level\":{
         #\"level\":\"HOST\",
         #\"cluster_name\":\"${cluster_name}\"
      #}
   #},
   #\"Requests/resource_filters\":[
      #{
         #\"service_name\":\"ATLAS\",
         #\"component_name\":\"ATLAS_SERVER\",
         #\"hosts\":\"${host}\"
      #}
   #]
#}" http://localhost:8080/api/v1/clusters/$cluster_name/requests  


        ## update zeppelin notebooks
        curl -sSL https://raw.githubusercontent.com/hortonworks-gallery/zeppelin-notebooks/master/update_all_notebooks.sh | sudo -E sh 
host=$(hostname -f)

  #update zeppelin configs by uncommenting admin user, enabling sessionManager/securityManager, switching from anon to authc
  #${ambari_config_get} zeppelin-shiro-ini \
    #| sed -e '1,4d' \
    #-e "s/^admin = admin, admin/admin = ${ambari_pass}, admin/"  \
    #-e "s/^user1 = .*/ivana-eu-hr = ${ambari_pass}, admin/" \
    #-e "s/^user2 = .*/compliance-admin = ${ambari_pass}, admin/" \
    #-e "s/^user3 = .*/joe-analyst = ${ambari_pass}, admin/" \
    #> /tmp/zeppelin-env.json

  #${ambari_config_set}  zeppelin-env /tmp/zeppelin-env.json
  #sleep 5
  #sudo curl -u admin:${ambari_pass} -H 'X-Requested-By: blah' -X POST -d "
#{
   #\"RequestInfo\":{
      #\"command\":\"RESTART\",
      #\"context\":\"Restart Zeppelin\",
      #\"operation_level\":{
         #\"level\":\"HOST\",
         #\"cluster_name\":\"${cluster_name}\"
      #}
   #},
   #\"Requests/resource_filters\":[
      #{
         #\"service_name\":\"ZEPPELIN\",
         #\"component_name\":\"ZEPPELIN_MASTER\",
         #\"hosts\":\"${host}\"
      #}
   #]
#}" http://localhost:8080/api/v1/clusters/${cluster_name}/requests  
        # TODO

        #ad_host="ad01.lab.hortonworks.net"
        #ad_root="ou=CorpUsers,dc=lab,dc=hortonworks,dc=net"
        #ad_user="cn=ldap-reader,ou=ServiceUsers,dc=lab,dc=hortonworks,dc=net"

        #sudo ambari-server setup-ldap \
          #--ldap-url=${ad_host}:389 \
          #--ldap-secondary-url= \
          #--ldap-ssl=false \
          #--ldap-base-dn=${ad_root} \
          #--ldap-manager-dn=${ad_user} \
          #--ldap-bind-anonym=false \
          #--ldap-dn=distinguishedName \
          #--ldap-member-attr=member \
          #--ldap-group-attr=cn \
          #--ldap-group-class=group \
          #--ldap-user-class=user \
          #--ldap-user-attr=sAMAccountName \
          #--ldap-save-settings \
          #--ldap-bind-anonym=false \
          #--ldap-referral=

        #echo hadoop-users,hr,sales,legal,hadoop-admins,compliance,analyst,eu_employees,us_employees > groups.txt
        #sudo ambari-server restart
        #sudo ambari-server sync-ldap --groups groups.txt

    fi
fi

